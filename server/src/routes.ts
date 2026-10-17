import { Hono } from "hono";
import type postgres from "postgres";
import { cors } from "hono/cors";
import { sql } from "./db.js";
import { moneyForecast } from "./forecast.js";
import { storeFile } from "./storage.js";
import { draftTasks, proposeTasks, rememberSubtask, reviewProof } from "./woolly.js";

export const app = new Hono();
app.use("/api/*", cors());
app.onError((error, c) => {
  console.error(error);
  return c.json({ error: error.message || "Something went wrong." }, 500);
});

type LinkRow = { id: string; url: string; label: string };
type FileRow = { id: string; path: string; filename: string };

app.get("/api/health", (c) => c.json({ ok: true }));

app.get("/api/people", async (c) => {
  const people = await sql`select id, name, role from people order by role, name`;
  return c.json({ people });
});

app.get("/api/workspace", async (c) => {
  const personId = c.req.query("personId") ?? "";
  const workspace = await loadWorkspace(personId);
  if (!workspace) return c.json({ error: "Person not found." }, 404);
  return c.json({ workspace });
});

app.post("/api/projects", async (c) => {
  const body = await c.req.json();
  const person = await personRow(String(body.personId || ""));
  if (!person || person.role !== "client") return c.json({ error: "Only a client can open a project." }, 403);
  const parsed = readProject(body);
  if ("error" in parsed) return c.json({ error: parsed.error }, 400);
  try {
    await sql.begin(async (tx) => {
      const [row] = await tx<{ id: string }[]>`
        insert into projects (client_id, worker_id, title, description, starts_on, ends_on, budget_cents)
        values (
          ${person.id},
          ${null},
          ${parsed.title},
          ${parsed.description},
          ${parsed.startsOn},
          ${parsed.endsOn},
          ${parsed.budgetCents}
        )
        returning id
      `;
      await applyCycles(tx, row.id, parsed.budgetCents, parsed.cycles, []);
    });
  } catch (error) {
    if (error instanceof RequestError) return c.json({ error: error.message }, 400);
    throw error;
  }
  return c.json({ workspace: await loadWorkspace(person.id) });
});

app.patch("/api/projects/:id", async (c) => {
  const project = await projectRow(c.req.param("id"));
  if (!project) return c.json({ error: "Project not found." }, 404);
  const body = await c.req.json();
  const person = await personRow(String(body.personId || ""));
  if (!person || person.role !== "client" || person.id !== project.client_id) {
    return c.json({ error: "Only the client can edit this project." }, 403);
  }
  const parsed = readProject(body);
  if ("error" in parsed) return c.json({ error: parsed.error }, 400);
  try {
    await sql.begin(async (tx) => {
      await tx`
        update projects
        set title = ${parsed.title},
            description = ${parsed.description},
            starts_on = ${parsed.startsOn},
            ends_on = ${parsed.endsOn},
            budget_cents = ${parsed.budgetCents}
        where id = ${project.id}
      `;
      await applyCycles(tx, project.id, parsed.budgetCents, parsed.cycles, parsed.removedCycleIds);
    });
  } catch (error) {
    if (error instanceof RequestError) return c.json({ error: error.message }, 400);
    throw error;
  }
  return c.json({ workspace: await loadWorkspace(person.id) });
});

app.delete("/api/projects/:id", async (c) => {
  const project = await projectRow(c.req.param("id"));
  if (!project) return c.json({ error: "Project not found." }, 404);
  const person = await personRow(c.req.query("personId") ?? "");
  if (!person || person.role !== "client" || person.id !== project.client_id) {
    return c.json({ error: "Only the client can delete this project." }, 403);
  }
  await sql`delete from projects where id = ${project.id}`;
  return c.json({ workspace: await loadWorkspace(person.id) });
});

app.post("/api/projects/:id/iterations", async (c) => {
  const project = await projectRow(c.req.param("id"));
  if (!project) return c.json({ error: "Project not found." }, 404);
  const body = await c.req.json();
  const payCents = dollarsToCents(body.allocation ?? body.pay);
  if (!payCents) return c.json({ error: "Each cycle needs an allocation." }, 400);
  const title = String(body.title || "").trim();
  if (!title) return c.json({ error: "Each cycle needs a title." }, 400);
  const [budget] = await sql<{ budget_cents: number | null }[]>`
    select budget_cents from projects where id = ${project.id}
  `;
  if (budget.budget_cents == null) {
    return c.json({ error: "Set a project budget before allocating a cycle." }, 400);
  }
  const [sum] = await sql<{ total: number }[]>`
    select coalesce(sum(pay_cents), 0)::int as total from iterations where project_id = ${project.id}
  `;
  if (Number(sum.total) + payCents > budget.budget_cents) {
    return c.json({
      error: `Allocations are ${moneyLabel(Number(sum.total) + payCents - budget.budget_cents)} over the budget.`,
    }, 400);
  }
  await sql`
    insert into iterations (project_id, title, pay_cents, deadline, brief)
    values (
      ${project.id},
      ${title},
      ${payCents},
      ${body.deadline || null},
      ${String(body.brief || "")}
    )
  `;
  return c.json({ workspace: await loadWorkspace(project.client_id) });
});

app.post("/api/iterations/:id/draft", async (c) => {
  const iteration = await iterationRow(c.req.param("id"));
  if (!iteration) return c.json({ error: "Iteration not found." }, 404);
  if (iteration.status !== "draft") {
    return c.json({ error: "This iteration is locked. Start another iteration to change the agreement." }, 409);
  }
  const brief = String((await c.req.json().catch(() => ({}))).brief ?? iteration.brief).trim();
  if (!brief) return c.json({ error: "Describe the work to split." }, 400);
  await sql`update iterations set brief = ${brief} where id = ${iteration.id}`;
  const tasks = await draftTasks(brief);
  await sql`delete from tasks where iteration_id = ${iteration.id}`;
  for (const task of tasks) {
    const [row] = await sql<{ id: string }[]>`
      insert into tasks (iteration_id, title, description)
      values (${iteration.id}, ${task.title}, ${task.description})
      returning id
    `;
    for (const subtask of task.subtasks) {
      const [child] = await sql<{ id: string }[]>`
        insert into subtasks (task_id, title, description, effort, value)
        values (${row.id}, ${subtask.title}, ${subtask.description}, ${subtask.effort}, ${subtask.value})
        returning id
      `;
      await rememberSubtask(child.id, subtask.title, subtask.description);
    }
  }
  return c.json({ workspace: await loadWorkspace(iteration.client_id) });
});

app.post("/api/tasks/propose", async (c) => {
  const body = await c.req.json();
  const person = await personRow(String(body.personId || ""));
  if (!person) return c.json({ error: "Person not found." }, 404);
  const summary = String(body.summary || "").trim();
  if (!summary) return c.json({ error: "Describe the work." }, 400);
  const workspace = await loadWorkspace(person.id);
  if (!workspace) return c.json({ error: "Person not found." }, 404);
  const cycles = workspace.projects.flatMap((project) =>
    project.iterations.map((iteration) => ({
      projectId: project.id,
      projectTitle: project.title,
      iterationId: iteration.id,
      iterationTitle: iteration.title,
      status: iteration.status,
    })),
  );
  if (!cycles.length) return c.json({ error: "There is no cycle to add tasks to." }, 409);
  const proposals = await proposeTasks(summary, cycles);
  return c.json({ proposals });
});

app.post("/api/tasks/accept", async (c) => {
  const body = await c.req.json();
  const person = await personRow(String(body.personId || ""));
  if (!person) return c.json({ error: "Person not found." }, 404);
  const workspace = await loadWorkspace(person.id);
  if (!workspace) return c.json({ error: "Person not found." }, 404);
  const knownCycles = new Set(
    workspace.projects.flatMap((project) => project.iterations.map((iteration) => iteration.id)),
  );
  const tasks = Array.isArray(body.tasks) ? body.tasks : [];
  if (!tasks.length) return c.json({ error: "Add at least one task." }, 400);
  const ready: { title: string; description: string; iterationId: string; review: string }[] = tasks.map((task: { title?: string; description?: string; iterationId?: string; review?: string }) => ({
    title: String(task.title || "").trim(),
    description: String(task.description || "").trim(),
    iterationId: String(task.iterationId || ""),
    review: task.review === "needs_revision" ? "needs_revision" : "open",
  }));
  if (ready.some((task) => !task.title || !task.description)) {
    return c.json({ error: "A task needs a title and a description." }, 400);
  }
  if (ready.some((task) => !knownCycles.has(task.iterationId))) {
    return c.json({ error: "Choose a cycle for each task." }, 409);
  }
  if (tasks.some((task: { review?: string }) => task.review !== "open" && task.review !== "needs_revision")) {
    return c.json({ error: "Mark each task approved or needs revision." }, 400);
  }
  for (const task of ready) {
    const [row] = await sql<{ id: string }[]>`
      insert into tasks (iteration_id, title, description, review)
      values (${task.iterationId}, ${task.title}, ${task.description}, ${task.review})
      returning id
    `;
    const [child] = await sql<{ id: string }[]>`
      insert into subtasks (task_id, title, description, effort, value)
      values (${row.id}, ${task.title}, ${task.description}, 1, 1)
      returning id
    `;
    await rememberSubtask(child.id, task.title, task.description);
  }
  return c.json({ workspace: await loadWorkspace(person.id) });
});

app.post("/api/iterations/:id/tasks", async (c) => {
  const iteration = await iterationRow(c.req.param("id"));
  if (!iteration) return c.json({ error: "Iteration not found." }, 404);
  const body = await c.req.json();
  const title = String(body.title || "").trim();
  const description = String(body.description || "").trim();
  if (!title || !description) return c.json({ error: "A task needs a title and a description." }, 400);
  const [row] = await sql<{ id: string }[]>`
    insert into tasks (iteration_id, title, description)
    values (${iteration.id}, ${title}, ${description})
    returning id
  `;
  await saveLinks("task_links", "task_id", row.id, body.links);
  return c.json({ workspace: await loadWorkspace(iteration.client_id) });
});

app.post("/api/tasks/:id/subtasks", async (c) => {
  const task = await taskRow(c.req.param("id"));
  if (!task) return c.json({ error: "Task not found." }, 404);
  if (task.status !== "draft") {
    return c.json({ error: "This iteration is locked. Start another iteration to change the agreement." }, 409);
  }
  const body = await c.req.json();
  const title = String(body.title || "").trim();
  const description = String(body.description || "").trim();
  if (!title || !description) return c.json({ error: "A subtask needs a title and a description." }, 400);
  const [row] = await sql<{ id: string }[]>`
    insert into subtasks (task_id, title, description, effort, value)
    values (${task.id}, ${title}, ${description}, ${positive(body.effort, 1)}, ${nonNegative(body.value, 1)})
    returning id
  `;
  await saveLinks("subtask_links", "subtask_id", row.id, body.links);
  await rememberSubtask(row.id, title, description);
  return c.json({ workspace: await loadWorkspace(task.client_id) });
});

app.patch("/api/tasks/:id", async (c) => {
  const task = await taskRow(c.req.param("id"));
  if (!task) return c.json({ error: "Task not found." }, 404);
  const body = await c.req.json();
  const person = await personRow(String(body.personId || ""));
  if (!person) return c.json({ error: "Person not found." }, 404);
  const title = String(body.title ?? task.title).trim();
  const description = String(body.description ?? "").trim();
  if (!title) return c.json({ error: "A task needs a title." }, 400);

  const [current] = await sql<{ status: string; project_id: string }[]>`
    select t.status, i.project_id
    from tasks t join iterations i on i.id = t.iteration_id
    where t.id = ${task.id}
  `;
  if (!current) return c.json({ error: "Task not found." }, 404);

  const requested = String(body.status || current.status);
  const decision = String(body.decision || "");
  let status = current.status;
  const proofSummary = String(body.proofSummary || "").trim();
  const proofUrl = String(body.proofUrl || "").trim();
  let saveProof = false;

  if (decision === "approve" || decision === "revise") {
    if (person.role !== "client") return c.json({ error: "Only the client can review a task." }, 403);
    if (current.status !== "under_review") {
      return c.json({ error: "This task is not under review." }, 400);
    }
    status = decision === "approve" ? "complete" : "revision_needed";
  } else if (requested === "complete") {
    if (!proofSummary) return c.json({ error: "A summary of the proof is required." }, 400);
    status = person.role === "client" ? "complete" : "under_review";
    saveProof = true;
  } else if (requested === "open" || requested === "under_review" || requested === "revision_needed") {
    status = requested;
  } else {
    return c.json({ error: "That status isn't one of the task statuses." }, 400);
  }

  const iterationId = String(body.iterationId || "").trim();
  const iteration = iterationId ? await iterationRow(iterationId) : null;
  if (!iteration) return c.json({ error: "Choose a cycle for this task." }, 400);
  const [destination] = await sql<{ project_id: string }[]>`
    select project_id from iterations where id = ${iteration.id}
  `;
  if (!destination) return c.json({ error: "Choose a cycle for this task." }, 400);

  const assigneeIds = Array.isArray(body.assigneeIds)
    ? body.assigneeIds.map((id: unknown) => String(id))
    : [];
  if (assigneeIds.length > 0) {
    const known = await sql<{ id: string }[]>`
      select id from people where role = 'worker' and id in ${sql(assigneeIds)}
    `;
    if (known.length !== new Set(assigneeIds).size) {
      return c.json({ error: "Assign the task to a worker." }, 400);
    }
  }

  try {
    await sql.begin(async (tx) => {
      if (saveProof) {
        await tx`
          update tasks set
            title = ${title},
            description = ${description},
            status = ${status},
            iteration_id = ${iteration.id},
            proof_summary = ${proofSummary},
            proof_url = ${proofUrl}
          where id = ${task.id}
        `;
      } else {
        await tx`
          update tasks set
            title = ${title},
            description = ${description},
            status = ${status},
            iteration_id = ${iteration.id}
          where id = ${task.id}
        `;
      }
      await tx`delete from task_assignees where task_id = ${task.id}`;
      for (const personId of assigneeIds) {
        await tx`insert into task_assignees (task_id, person_id) values (${task.id}, ${personId})`;
      }
      if (Array.isArray(body.files)) {
        for (const file of body.files) {
          if (!file?.fileBase64) continue;
          const stored = await storeFile(
            String(file.filename || "proof"),
            decodeBase64(String(file.fileBase64)),
            String(file.contentType || ""),
          );
          await tx`
            insert into task_files (task_id, path, filename)
            values (${task.id}, ${stored.path}, ${stored.filename})
          `;
        }
      }
      if (Array.isArray(body.shares)) {
        await writeShares(tx, destination.project_id, body.shares);
      }
      if (current.project_id !== destination.project_id) {
        await rebalanceShares(tx, current.project_id);
      }
    });
  } catch (error) {
    if (error instanceof RequestError) return c.json({ error: error.message }, 400);
    throw error;
  }

  return c.json({ workspace: await loadWorkspace(person.id) });
});

app.patch("/api/subtasks/:id", async (c) => {
  const subtask = await subtaskRow(c.req.param("id"));
  if (!subtask) return c.json({ error: "Subtask not found." }, 404);
  if (subtask.status !== "draft") {
    return c.json({ error: "This iteration is locked. Start another iteration to change the agreement." }, 409);
  }
  const body = await c.req.json();
  const title = String(body.title ?? subtask.title).trim();
  const description = String(body.description ?? subtask.description).trim();
  if (!title || !description) return c.json({ error: "A subtask needs a title and a description." }, 400);
  await sql`
    update subtasks set
      title = ${title},
      description = ${description},
      effort = ${positive(body.effort, Number(subtask.effort))},
      value = ${nonNegative(body.value, Number(subtask.value))}
    where id = ${subtask.id}
  `;
  if (Array.isArray(body.links)) {
    await sql`delete from subtask_links where subtask_id = ${subtask.id}`;
    await saveLinks("subtask_links", "subtask_id", subtask.id, body.links);
  }
  await rememberSubtask(subtask.id, title, description);
  return c.json({ workspace: await loadWorkspace(subtask.client_id) });
});

app.delete("/api/tasks/:id", async (c) => {
  const task = await taskRow(c.req.param("id"));
  if (!task) return c.json({ error: "Task not found." }, 404);
  if (task.status !== "draft") {
    return c.json({ error: "This iteration is locked. Start another iteration to change the agreement." }, 409);
  }
  await sql`delete from tasks where id = ${task.id}`;
  return c.json({ workspace: await loadWorkspace(task.client_id) });
});

app.delete("/api/subtasks/:id", async (c) => {
  const subtask = await subtaskRow(c.req.param("id"));
  if (!subtask) return c.json({ error: "Subtask not found." }, 404);
  if (subtask.status !== "draft") {
    return c.json({ error: "This iteration is locked. Start another iteration to change the agreement." }, 409);
  }
  await sql`delete from subtasks where id = ${subtask.id}`;
  return c.json({ workspace: await loadWorkspace(subtask.client_id) });
});

app.post("/api/iterations/:id/lock", async (c) => {
  const iteration = await iterationRow(c.req.param("id"));
  if (!iteration) return c.json({ error: "Iteration not found." }, 404);
  const [{ count }] = await sql<{ count: string }[]>`
    select count(*) from subtasks s
    join tasks t on t.id = s.task_id
    where t.iteration_id = ${iteration.id}
  `;
  if (Number(count) === 0) return c.json({ error: "Add at least one subtask before locking." }, 400);
  await sql`update iterations set status = 'locked', locked_at = coalesce(locked_at, now()) where id = ${iteration.id}`;
  return c.json({ workspace: await loadWorkspace(iteration.client_id) });
});

app.post("/api/subtasks/:id/completion", async (c) => {
  const subtask = await subtaskRow(c.req.param("id"));
  if (!subtask) return c.json({ error: "Subtask not found." }, 404);
  if (subtask.status !== "locked") return c.json({ error: "Lock the iteration before submitting work." }, 409);
  const body = await c.req.json();
  const summary = String(body.summary || "").trim();
  const link = String(body.link || "").trim();
  const hasFile = Boolean(body.fileBase64);
  if (!summary && !link && !hasFile) return c.json({ error: "Add a summary, a link, or a file." }, 400);
  await sql`delete from completions where subtask_id = ${subtask.id}`;
  const [completion] = await sql<{ id: string }[]>`
    insert into completions (subtask_id, summary) values (${subtask.id}, ${summary}) returning id
  `;
  if (link) {
    await sql`insert into completion_links (completion_id, url, label) values (${completion.id}, ${link}, ${String(body.linkLabel || "")})`;
  }
  if (hasFile) {
    const stored = await storeFile(String(body.filename || "proof"), decodeBase64(body.fileBase64), String(body.contentType || ""));
    await sql`insert into completion_files (completion_id, path, filename) values (${completion.id}, ${stored.path}, ${stored.filename})`;
  }
  return c.json({ workspace: await loadWorkspace(subtask.client_id) });
});

app.post("/api/completions/:id/review", async (c) => {
  const completion = await completionContext(c.req.param("id"));
  if (!completion) return c.json({ error: "Completion not found." }, 404);
  const review = await reviewProof({
    title: completion.title,
    description: completion.description,
    summary: completion.summary,
    links: completion.links,
  });
  await sql`
    update completions set model_outcome = ${review.outcome}, model_reason = ${review.reason}
    where id = ${completion.id}
  `;
  return c.json({ workspace: await loadWorkspace(completion.client_id) });
});

app.post("/api/completions/:id/decide", async (c) => {
  const completion = await completionContext(c.req.param("id"));
  if (!completion) return c.json({ error: "Completion not found." }, 404);
  const body = await c.req.json();
  const outcome = body.outcome === "dispute" ? "dispute" : body.outcome === "credit" ? "credit" : "";
  if (!outcome) return c.json({ error: "Choose credit or dispute." }, 400);
  await sql`delete from decisions where completion_id = ${completion.id}`;
  await sql`
    insert into decisions (completion_id, approver_id, outcome, note)
    values (${completion.id}, ${completion.client_id}, ${outcome}, ${String(body.note || "")})
  `;
  return c.json({ workspace: await loadWorkspace(completion.client_id) });
});

async function loadWorkspace(personId: string) {
  const person = await personRow(personId);
  if (!person) return null;
  const projectIds = person.role === "client"
    ? await sql<{ id: string }[]>`select id from projects where client_id = ${person.id} order by created_at`
    : await sql<{ id: string }[]>`
        select id from projects p
        where p.worker_id = ${person.id}
          or exists (
            select 1 from iterations i
            join tasks t on t.iteration_id = i.id
            join task_assignees a on a.task_id = t.id
            where i.project_id = p.id and a.person_id = ${person.id}
          )
        order by created_at
      `;
  const projects = [];
  for (const row of projectIds) projects.push(await loadProject(row.id));
  const workers = await sql<{ id: string; name: string }[]>`
    select id, name from people where role = 'worker' order by name
  `;
  return {
    person: { id: person.id, name: person.name, role: person.role },
    workers,
    projects,
  };
}

async function loadProject(id: string) {
  const [project] = await sql<
    {
      id: string;
      title: string;
      description: string;
      starts_on: string | null;
      ends_on: string | null;
      budget_cents: number | null;
      client_name: string;
      worker_id: string | null;
      worker_name: string | null;
    }[]
  >`
    select p.id, p.title, p.description, p.starts_on::text, p.ends_on::text, p.budget_cents,
      client.name as client_name, p.worker_id, worker.name as worker_name
    from projects p
    join people client on client.id = p.client_id
    left join people worker on worker.id = p.worker_id
    where p.id = ${id}
  `;
  const iterationRows = await sql<{ id: string }[]>`
    select id from iterations where project_id = ${id} order by created_at
  `;
  const iterations = [];
  for (const row of iterationRows) iterations.push(await loadIteration(row.id));
  return {
    id: project.id,
    title: project.title,
    description: project.description,
    startsOn: project.starts_on,
    endsOn: project.ends_on,
    budgetCents: project.budget_cents,
    clientName: project.client_name,
    workerId: project.worker_id ?? "",
    workerName: project.worker_name ?? "",
    iterations,
  };
}

async function loadIteration(id: string) {
  const [iteration] = await sql<
    { id: string; title: string; pay_cents: number; deadline: string | null; brief: string; status: string; locked_at: Date | null }[]
  >`
    select id, title, pay_cents, deadline::text, brief, status, locked_at
    from iterations where id = ${id}
  `;
  const taskRows = await sql<
    {
      id: string;
      title: string;
      description: string;
      review: string;
      status: string;
      share_bps: number | null;
      proof_summary: string;
      proof_url: string;
    }[]
  >`
    select id, title, description, review, status, share_bps, proof_summary, proof_url
    from tasks where iteration_id = ${id} order by created_at
  `;
  const tasks = [];
  let totalEffort = 0;
  let acceptedEffort = 0;
  for (const task of taskRows) {
    const links = await sql<LinkRow[]>`select id, url, label from task_links where task_id = ${task.id}`;
    const assignees = await sql<{ id: string; name: string }[]>`
      select person.id, person.name
      from task_assignees assignee
      join people person on person.id = assignee.person_id
      where assignee.task_id = ${task.id}
      order by person.name
    `;
    const files = await publicFiles(await sql<FileRow[]>`select id, path, filename from task_files where task_id = ${task.id}`);
    const subtaskRows = await sql<{ id: string; title: string; description: string; effort: string; value: string }[]>`
      select id, title, description, effort::text, value::text
      from subtasks where task_id = ${task.id}
      order by value / effort desc, created_at
    `;
    const subtasks = [];
    for (const subtask of subtaskRows) {
      const effort = Number(subtask.effort);
      totalEffort += effort;
      const subtaskLinks = await sql<LinkRow[]>`select id, url, label from subtask_links where subtask_id = ${subtask.id}`;
      const subtaskFiles = await publicFiles(await sql<FileRow[]>`select id, path, filename from subtask_files where subtask_id = ${subtask.id}`);
      const [completion] = await sql<
        { id: string; summary: string; model_outcome: string | null; model_reason: string | null }[]
      >`select id, summary, model_outcome, model_reason from completions where subtask_id = ${subtask.id} order by created_at desc limit 1`;
      let proof = null;
      if (completion) {
        const [decision] = await sql<{ outcome: string; note: string }[]>`
          select outcome, note from decisions where completion_id = ${completion.id} order by created_at desc limit 1
        `;
        if (decision?.outcome === "credit") acceptedEffort += effort;
        proof = {
          id: completion.id,
          summary: completion.summary,
          links: await sql<LinkRow[]>`select id, url, label from completion_links where completion_id = ${completion.id}`,
          files: await publicFiles(await sql<FileRow[]>`select id, path, filename from completion_files where completion_id = ${completion.id}`),
          modelOutcome: completion.model_outcome,
          modelReason: completion.model_reason,
          decision: decision ?? null,
        };
      }
      subtasks.push({
        id: subtask.id,
        title: subtask.title,
        description: subtask.description,
        effort,
        value: Number(subtask.value),
        links: subtaskLinks,
        files: subtaskFiles,
        completion: proof,
      });
    }
    tasks.push({
      id: task.id,
      title: task.title,
      description: task.description,
      review: task.review,
      status: task.status,
      shareBps: task.share_bps,
      proofSummary: task.proof_summary,
      proofUrl: task.proof_url,
      links,
      files,
      assignees,
      subtasks,
    });
  }
  const money = moneyForecast({
    payCents: iteration.pay_cents,
    totalEffort,
    acceptedEffort,
    lockedAt: iteration.locked_at,
    deadline: iteration.deadline,
  });
  return {
    id: iteration.id,
    title: iteration.title,
    payCents: iteration.pay_cents,
    deadline: iteration.deadline,
    brief: iteration.brief,
    status: iteration.status,
    tasks,
    ...money,
  };
}

async function publicFiles(rows: FileRow[]) {
  const { env } = await import("./env.js");
  return rows.map((file) => ({
    ...file,
    url: `${env.supabaseUrl}/storage/v1/object/public/woolly/${file.path}`,
  }));
}

async function personRow(id: string) {
  const [row] = await sql<{ id: string; name: string; role: string }[]>`
    select id, name, role from people where id = ${id}
  `;
  return row;
}

async function projectRow(id: string) {
  const [row] = await sql<{ id: string; client_id: string; worker_id: string }[]>`
    select id, client_id, worker_id from projects where id = ${id}
  `;
  return row;
}

async function iterationRow(id: string) {
  const [row] = await sql<{ id: string; status: string; brief: string; client_id: string }[]>`
    select i.id, i.status, i.brief, p.client_id
    from iterations i join projects p on p.id = i.project_id
    where i.id = ${id}
  `;
  return row;
}

async function taskRow(id: string) {
  const [row] = await sql<{ id: string; title: string; description: string; status: string; client_id: string }[]>`
    select t.id, t.title, t.description, i.status, p.client_id
    from tasks t
    join iterations i on i.id = t.iteration_id
    join projects p on p.id = i.project_id
    where t.id = ${id}
  `;
  return row;
}

async function subtaskRow(id: string) {
  const [row] = await sql<
    { id: string; title: string; description: string; effort: string; value: string; status: string; client_id: string }[]
  >`
    select s.id, s.title, s.description, s.effort::text, s.value::text, i.status, p.client_id
    from subtasks s
    join tasks t on t.id = s.task_id
    join iterations i on i.id = t.iteration_id
    join projects p on p.id = i.project_id
    where s.id = ${id}
  `;
  return row;
}

async function completionContext(id: string) {
  const [row] = await sql<
    { id: string; client_id: string; title: string; description: string; summary: string }[]
  >`
    select k.id, p.client_id, s.title, s.description, k.summary
    from completions k
    join subtasks s on s.id = k.subtask_id
    join tasks t on t.id = s.task_id
    join iterations i on i.id = t.iteration_id
    join projects p on p.id = i.project_id
    where k.id = ${id}
  `;
  if (!row) return null;
  const links = await sql<{ url: string }[]>`select url from completion_links where completion_id = ${id}`;
  return { ...row, links: links.map((link) => link.url) };
}

async function saveLinks(
  table: "task_links" | "subtask_links",
  column: "task_id" | "subtask_id",
  id: string,
  links: { url?: string; label?: string }[] | undefined,
) {
  for (const link of links ?? []) {
    const url = String(link.url || "").trim();
    if (!url) continue;
    if (table === "task_links") {
      await sql`insert into task_links (task_id, url, label) values (${id}, ${url}, ${String(link.label || "")})`;
    } else {
      await sql`insert into subtask_links (subtask_id, url, label) values (${id}, ${url}, ${String(link.label || "")})`;
    }
  }
  void column;
}

type ShareInput = { taskId?: string; percent?: number };

async function writeShares(
  tx: postgres.TransactionSql,
  projectId: string,
  shares: ShareInput[],
) {
  const tasks = await tx<{ id: string }[]>`
    select t.id from tasks t
    join iterations i on i.id = t.iteration_id
    where i.project_id = ${projectId}
    order by t.created_at
  `;
  const ids = tasks.map((row) => String(row.id));
  const byId = new Map(shares.map((share) => [String(share.taskId || ""), Number(share.percent)]));
  if (ids.some((id) => !Number.isFinite(byId.get(id)))) {
    throw new RequestError("Every task in the project needs a share.");
  }
  const percents = ids.map((id) => Math.max(0, Math.round(byId.get(id) ?? 0)));
  const total = percents.reduce((sum, value) => sum + value, 0);
  const weights = total === 0 ? equalParts(ids.length, 100) : percents;
  const basis = total === 0 ? 100 : total;
  const bps = weights.map((value) => Math.round((value / basis) * 10000));
  const drift = 10000 - bps.reduce((sum, value) => sum + value, 0);
  if (bps.length > 0) bps[0] += drift;
  for (let index = 0; index < ids.length; index += 1) {
    await tx`update tasks set share_bps = ${bps[index]} where id = ${ids[index]}`;
  }
}

async function rebalanceShares(tx: postgres.TransactionSql, projectId: string) {
  const rows = await tx<{ id: string; share_bps: number | null }[]>`
    select t.id, t.share_bps from tasks t
    join iterations i on i.id = t.iteration_id
    where i.project_id = ${projectId}
    order by t.created_at
  `;
  if (rows.length === 0 || rows.some((row) => row.share_bps == null)) return;
  const total = rows.reduce((sum, row) => sum + (row.share_bps ?? 0), 0);
  const bps = total === 0
    ? equalParts(rows.length, 10000)
    : rows.map((row) => Math.round(((row.share_bps ?? 0) / total) * 10000));
  const drift = 10000 - bps.reduce((sum, value) => sum + value, 0);
  if (bps.length > 0) bps[0] += drift;
  for (let index = 0; index < rows.length; index += 1) {
    await tx`update tasks set share_bps = ${bps[index]} where id = ${rows[index].id}`;
  }
}

function equalParts(count: number, whole: number) {
  if (count === 0) return [];
  const base = Math.floor(whole / count);
  let extra = whole - base * count;
  return Array.from({ length: count }, () => base + (extra-- > 0 ? 1 : 0));
}

class RequestError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RequestError";
  }
}

type CycleWrite = { id: string | null; title: string; allocationCents: number };

type ProjectInput = {
  title: string;
  description: string;
  startsOn: string | null;
  endsOn: string | null;
  budgetCents: number;
  cycles: CycleWrite[];
  removedCycleIds: string[];
};

function readProject(body: Record<string, unknown>): ProjectInput | { error: string } {
  const title = String(body.title || "").trim();
  if (!title) return { error: "A project needs a title." };
  const budgetCents = dollarsToCents(body.budget);
  if (!budgetCents) return { error: "A project needs a budget." };
  const starts = readDate(body.startsOn, "Start date");
  if ("error" in starts) return starts;
  const ends = readDate(body.endsOn, "End date");
  if ("error" in ends) return ends;
  if (starts.date && ends.date && ends.date < starts.date) {
    return { error: "End date is before the start date." };
  }
  const cycles = readCycles(body.cycles);
  if ("error" in cycles) return cycles;
  const removed = readRemoved(body.removedCycleIds);
  if ("error" in removed) return removed;
  return {
    title,
    description: String(body.description || "").trim(),
    startsOn: starts.date,
    endsOn: ends.date,
    budgetCents,
    cycles: cycles.cycles,
    removedCycleIds: removed.ids,
  };
}

async function applyCycles(
  tx: postgres.TransactionSql,
  projectId: string,
  budgetCents: number,
  cycles: CycleWrite[],
  removedIds: string[],
) {
  const existing = await tx<{ id: string; pay_cents: number }[]>`
    select id, pay_cents from iterations where project_id = ${projectId}
  `;
  const existingIds = new Set(existing.map((row) => row.id));
  const removed = new Set(removedIds);
  for (const id of removed) {
    if (!existingIds.has(id)) throw new RequestError("That cycle is not on this project.");
  }
  const seen = new Set<string>();
  let total = 0;
  for (const cycle of cycles) {
    if (cycle.id) {
      if (!existingIds.has(cycle.id)) throw new RequestError("That cycle is not on this project.");
      if (removed.has(cycle.id)) throw new RequestError("A removed cycle can't be saved.");
      if (seen.has(cycle.id)) throw new RequestError("Each cycle can only be saved once.");
      seen.add(cycle.id);
    }
    total += cycle.allocationCents;
  }
  for (const row of existing) {
    if (!seen.has(row.id) && !removed.has(row.id)) total += Number(row.pay_cents);
  }
  if (total > budgetCents) {
    throw new RequestError(`Allocations are ${moneyLabel(total - budgetCents)} over the budget.`);
  }
  for (const id of removed) {
    await tx`delete from iterations where id = ${id} and project_id = ${projectId}`;
  }
  for (const cycle of cycles) {
    if (cycle.id) {
      await tx`
        update iterations set title = ${cycle.title}, pay_cents = ${cycle.allocationCents}
        where id = ${cycle.id} and project_id = ${projectId}
      `;
    } else {
      await tx`
        insert into iterations (project_id, title, pay_cents)
        values (${projectId}, ${cycle.title}, ${cycle.allocationCents})
      `;
    }
  }
}

function moneyLabel(cents: number) {
  const absolute = Math.abs(Math.round(cents));
  const dollars = Math.floor(absolute / 100);
  const remainder = String(absolute % 100).padStart(2, "0");
  return `$${dollars}.${remainder}`;
}

function readDate(value: unknown, label: string): { date: string | null } | { error: string } {
  const text = value == null ? "" : String(value).trim();
  if (!text) return { date: null };
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!match) return { error: `${label} needs a real date.` };
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const utc = new Date(Date.UTC(year, month - 1, day));
  if (utc.getUTCFullYear() !== year || utc.getUTCMonth() !== month - 1 || utc.getUTCDate() !== day) {
    return { error: `${label} needs a real date.` };
  }
  return { date: text };
}

function readCycles(value: unknown): { cycles: CycleWrite[] } | { error: string } {
  if (value == null) return { cycles: [] };
  if (!Array.isArray(value)) return { error: "Cycles need to be a list." };
  const cycles: CycleWrite[] = [];
  for (const item of value) {
    const record = item && typeof item === "object" ? item as Record<string, unknown> : {};
    const title = String(record.title || "").trim();
    const allocation = record.allocation ?? record.pay;
    const allocationText = allocation == null ? "" : String(allocation).trim();
    const id = String(record.id || "").trim();
    if (!id && !title && !allocationText) continue;
    if (!title) return { error: "Each cycle needs a title." };
    const allocationCents = dollarsToCents(allocation);
    if (!allocationCents) return { error: "Each cycle needs an allocation." };
    cycles.push({ id: id || null, title, allocationCents });
  }
  return { cycles };
}

function readRemoved(value: unknown): { ids: string[] } | { error: string } {
  if (value == null) return { ids: [] };
  if (!Array.isArray(value)) return { error: "Removed cycles need to be a list." };
  return { ids: value.map((item) => String(item || "").trim()).filter((id) => id.length > 0) };
}

function dollarsToCents(value: unknown) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) return 0;
  return Math.round(amount * 100);
}

function positive(value: unknown, fallback: number) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : fallback;
}

function nonNegative(value: unknown, fallback: number) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : fallback;
}

function decodeBase64(value: string) {
  const cleaned = value.includes(",") ? value.slice(value.indexOf(",") + 1) : value;
  return new Uint8Array(Buffer.from(cleaned, "base64"));
}
