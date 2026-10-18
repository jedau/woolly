# Woolly

Pay for an iteration, measured by the subtasks a client accepts.

A project is the epic. An iteration is one sprint inside that project: it has an amount and an optional deadline. Tasks are the stories. Subtasks are the tickets. Pay for an iteration is its amount times the share of subtask effort the client has credited.

A client has many workers. A worker has many projects. The client adds work and reviews it, filtered by worker or by project. The worker adds and edits tasks, and submits subtasks for review. The worker cannot credit their own work.

The people in the demo are fictional: Cool Client (client), Worker One (worker), and Worker Dos (worker).

## Demo

Walkthrough of the client board, task allocation, Manage, and the worker account: https://youtu.be/IX1FJzK4vcU

## Look

Dark brown, flat, closer to a Darcula editor than a paper form. Near-black background, warm brown panels, amber marks for the current selection and the primary button. Green means credited. Red means disputed.

Sign-in is a short account list. After that, the client and the worker get different sidebars.

- **Client.** Workers on the left, then projects. Choosing a worker filters the projects. The main area is the open project: its iterations, then each task, then the subtasks. Submitted subtasks show a recommendation and Credit or Dispute.
- **Worker.** Projects only. The same hierarchy, with Submit for review on open subtasks, and no credit button.

## Test

With both processes running:

- App: http://127.0.0.1:8080
- API: http://127.0.0.1:8787

1. Sign in as **Cool Client**. The sidebar lists Worker One and Worker Dos, and two projects.
2. Open **Northwind portal**. Sprint 1 is locked. “Mark an order packed” is already credited. “Monday email” is in review: click **Review**, then **Credit** or **Dispute**. The accepted amount on Sprint 1 changes.
3. Choose **Worker Dos** in the sidebar. The only project left is **Field notes**.
4. Sign out. Sign in as **Worker One**. Only Northwind portal is listed. Sprint 1 has no Credit button. “Signed-in order list” can be submitted. Sprint 2 is a draft: edit the brief, **Break into tasks**, or **Add task**. Worker One cannot lock the iteration.
5. Sign in as **Worker Dos** to see Field notes from the worker side.

## Run

```bash
cd server && npm install && npm run migrate && npm run dev
cd app && flutter run -d chrome
```

`npm run migrate` rebuilds the project tables and the demo rows. Copy `.env.example` to `.env` first. The API listens on `http://localhost:8787`.

## License

MIT
