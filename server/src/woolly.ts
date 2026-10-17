import { google } from "@ai-sdk/google";
import { createTool } from "@mastra/core/tools";
import { Agent } from "@mastra/core/agent";
import { z } from "zod";
import { sql } from "./db.js";
import { embedText, geminiText, parseJson } from "./gemini.js";
import { env } from "./env.js";

export type DraftSubtask = {
  title: string;
  description: string;
  effort: number;
  value: number;
};

export type DraftTask = {
  title: string;
  description: string;
  subtasks: DraftSubtask[];
};

export type Review = { outcome: "credit" | "dispute"; reason: string };

async function similarWork(query: string) {
  const embedding = await embedText(query);
  const vectorRows = embedding
    ? await sql<{ title: string; description: string; similarity: number }[]>`
        select title, description, 1 - (embedding <=> ${JSON.stringify(embedding)}::vector) as similarity
        from subtasks
        where embedding is not null
        order by embedding <=> ${JSON.stringify(embedding)}::vector
        limit 5
      `
    : [];
  const keywordRows = await sql<{ title: string; description: string }[]>`
    select title, description
    from subtasks
    where search_text @@ plainto_tsquery('english', ${query})
    limit 5
  `;
  const seen = new Set<string>();
  const items = [];
  for (const row of [...vectorRows, ...keywordRows]) {
    const key = row.title;
    if (seen.has(key)) continue;
    seen.add(key);
    items.push({ title: row.title, description: row.description });
  }
  return items.slice(0, 5);
}

export const searchPastWork = createTool({
  id: "search-past-work",
  description: "Find accepted work with a similar title or description.",
  inputSchema: z.object({ query: z.string() }),
  outputSchema: z.object({
    items: z.array(z.object({ title: z.string(), description: z.string() })),
  }),
  execute: async ({ query }) => ({ items: await similarWork(query) }),
});

const splitAgent = new Agent({
  id: "woolly-split",
  name: "Woolly split",
  instructions: `You split a body of work into tasks and subtasks for one iteration of a project.
A task is a story. A subtask is the ticket someone finishes and submits.
Call search-past-work before you answer.
Return JSON only, with this shape:
{"assumptions":["..."],"tasks":[{"title":"","description":"","subtasks":[{"title":"","description":"","effort":1,"value":1}]}]}
Subtask description is the acceptance criteria.
effort is a positive relative size. value is how much it matters, from 0 to 5.
Prefer several small subtasks over one large one.`,
  model: google(env.geminiModel),
  tools: { searchPastWork },
});

const reviewAgent = new Agent({
  id: "woolly-review",
  name: "Woolly review",
  instructions: `You compare proof of finished work with the subtask title and description.
Call search-past-work before you answer.
Return JSON only:
{"outcome":"credit","reason":"..."} or {"outcome":"dispute","reason":"..."}
credit means the proof shows the description was met. dispute means it does not.
The reason must mention the description, not a hunch.`,
  model: google(env.geminiModel),
  tools: { searchPastWork },
});

function cleanTasks(value: {
  tasks?: Array<DraftTask & { effort?: number; value?: number }>;
}): DraftTask[] {
  const tasks = (value.tasks ?? [])
    .map((task) => {
      const title = String(task.title ?? "").trim();
      const description = String(task.description ?? "").trim();
      const subtasks = (task.subtasks ?? [])
        .map((subtask) => ({
          title: String(subtask.title ?? "").trim(),
          description: String(subtask.description ?? "").trim(),
          effort: Number(subtask.effort) > 0 ? Number(subtask.effort) : 1,
          value: Number(subtask.value) >= 0 ? Number(subtask.value) : 1,
        }))
        .filter((subtask) => subtask.title && subtask.description);
      if (!subtasks.length && title && description) {
        subtasks.push({
          title,
          description,
          effort: Number(task.effort) > 0 ? Number(task.effort) : 1,
          value: Number(task.value) >= 0 ? Number(task.value) : 1,
        });
      }
      return { title, description, subtasks };
    })
    .filter((task) => task.title && task.description && task.subtasks.length);
  if (!tasks.length) throw new Error("The model did not return any tasks");
  return tasks;
}

async function agentJson<T>(agent: Agent, prompt: string): Promise<T> {
  try {
    const result = await agent.generate(prompt, { maxSteps: 5 });
    const text = typeof result.text === "string" ? result.text : "";
    if (text) return parseJson<T>(text);
  } catch (error) {
    console.error("Mastra generate failed:", error instanceof Error ? error.message : error);
  }
  return parseJson<T>(await geminiText(prompt));
}

export type CycleChoice = {
  projectId: string;
  projectTitle: string;
  iterationId: string;
  iterationTitle: string;
  status: string;
};

export type ProposedTask = {
  title: string;
  description: string;
  projectId: string;
  iterationId: string;
  note: string;
};

const placeAgent = new Agent({
  id: "woolly-place",
  name: "Woolly place",
  instructions: `You turn a summary into one task for each piece of work it names.
A task is a story. Return JSON only:
{"tasks":[{"title":"","description":"","cycle":"","project":""}]}
Copy cycle as the cycle title from the summary, such as "Cycle 1".
Copy project as the project title when the summary names one, otherwise leave it empty.
Return every named task. A missing or past cycle is still a task: keep the cycle title and do not substitute a different cycle.
The description is one or two sentences.`,
  model: google(env.geminiModel),
});

function sameText(left: string, right: string) {
  return left.trim().toLowerCase() === right.trim().toLowerCase();
}

function cycleLabel(raw: string) {
  const match = raw.trim().match(/cycle\s+(\d+)/i);
  return match ? `Cycle ${match[1]}` : raw.trim();
}

function cleanTitle(raw: string) {
  return raw.trim().replace(/^(?:(?:and|add|to)\s+)+/i, "").trim();
}

function explicitAssignments(summary: string) {
  const found: Array<{ title: string; cycle: string }> = [];
  for (const match of summary.matchAll(/([^,;\n]+?)\s+to\s+(cycle\s+\d+)/gi)) {
    const title = cleanTitle(match[1]);
    const cycle = cycleLabel(match[2]);
    if (title && !found.some((item) => sameText(item.title, title))) found.push({ title, cycle });
  }
  return found;
}

function placeTask(
  title: string,
  description: string,
  cycleTitle: string,
  projectTitle: string,
  cycles: CycleChoice[],
): ProposedTask {
  const label = cycleLabel(cycleTitle);
  const namedProject = cycles.find((cycle) => sameText(cycle.projectTitle, projectTitle));
  const titled = label ? cycles.filter((cycle) => sameText(cycle.iterationTitle, label)) : [];
  const matches = namedProject ? titled.filter((cycle) => cycle.projectId === namedProject.projectId) : titled;
  if (matches.length === 1) {
    return {
      title,
      description,
      projectId: matches[0].projectId,
      iterationId: matches[0].iterationId,
      note: "",
    };
  }
  if (matches.length > 1) {
    return {
      title,
      description,
      projectId: namedProject?.projectId ?? "",
      iterationId: "",
      note: `${label} is on more than one project.`,
    };
  }
  return {
    title,
    description,
    projectId: namedProject?.projectId ?? "",
    iterationId: "",
    note: label ? `${label} isn't a cycle yet.` : "Choose a cycle.",
  };
}

export async function proposeTasks(summary: string, cycles: CycleChoice[]): Promise<ProposedTask[]> {
  const parsed = await agentJson<{
    tasks?: Array<{ title?: string; description?: string; cycle?: string; project?: string }>;
  }>(
    placeAgent,
    `Cycles:\n${JSON.stringify(
      cycles.map((cycle) => ({
        project: cycle.projectTitle,
        cycle: cycle.iterationTitle,
      })),
    )}\n\nSummary:\n${summary}`,
  );
  const items = (parsed.tasks ?? [])
    .map((task) => ({
      title: String(task.title ?? "").trim(),
      description: String(task.description ?? "").trim(),
      cycle: cycleLabel(String(task.cycle ?? "")),
      project: String(task.project ?? "").trim(),
    }))
    .filter((task) => task.title);
  for (const extra of explicitAssignments(summary)) {
    const existing = items.find((task) => sameText(cleanTitle(task.title), extra.title));
    if (existing) {
      existing.title = extra.title;
      existing.cycle = extra.cycle;
    } else {
      items.push({ title: extra.title, description: extra.title, cycle: extra.cycle, project: "" });
    }
  }
  const placed = items
    .filter((task) => task.description)
    .map((task) => placeTask(task.title, task.description, task.cycle, task.project, cycles));
  if (!placed.length) throw new Error("That summary did not name any tasks.");
  return placed;
}

export async function draftTasks(brief: string): Promise<DraftTask[]> {
  const past = await similarWork(brief);
  const parsed = await agentJson<{ tasks: DraftTask[] }>(
    splitAgent,
    `Past accepted work:\n${JSON.stringify(past)}\n\nBrief:\n${brief}`,
  );
  return cleanTasks(parsed);
}

export async function reviewProof(input: {
  title: string;
  description: string;
  summary: string;
  links: string[];
}): Promise<Review> {
  const past = await similarWork(`${input.title}\n${input.description}`);
  const parsed = await agentJson<Review>(
    reviewAgent,
    `Past accepted work:\n${JSON.stringify(past)}\n\nSubtask title: ${input.title}\nSubtask description: ${input.description}\nProof summary: ${input.summary || "(none)"}\nProof links: ${input.links.join(", ") || "(none)"}`,
  );
  if (parsed.outcome !== "credit" && parsed.outcome !== "dispute") {
    throw new Error("The model did not return a credit or dispute");
  }
  return { outcome: parsed.outcome, reason: String(parsed.reason ?? "").trim() || "No reason given." };
}

export async function rememberSubtask(subtaskId: string, title: string, description: string) {
  const embedding = await embedText(`${title}\n${description}`);
  if (!embedding) return;
  await sql`
    update subtasks set embedding = ${JSON.stringify(embedding)}::vector where id = ${subtaskId}
  `;
}
