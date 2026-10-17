create extension if not exists vector;
create extension if not exists pgcrypto;

drop table if exists decisions cascade;
drop table if exists completion_files cascade;
drop table if exists completion_links cascade;
drop table if exists completions cascade;
drop table if exists subtask_files cascade;
drop table if exists subtask_links cascade;
drop table if exists subtasks cascade;
drop table if exists task_files cascade;
drop table if exists task_links cascade;
drop table if exists task_assignees cascade;
drop table if exists tasks cascade;
drop table if exists iterations cascade;
drop table if exists projects cascade;
drop table if exists cycles cascade;

create table if not exists people (
  id uuid primary key,
  name text not null,
  role text not null check (role in ('client', 'worker'))
);

create table projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references people(id),
  worker_id uuid references people(id),
  title text not null,
  description text not null default '',
  starts_on date,
  ends_on date,
  budget_cents integer,
  created_at timestamptz not null default now(),
  check (budget_cents is null or budget_cents > 0),
  check (starts_on is null or ends_on is null or ends_on >= starts_on)
);

create table iterations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  title text not null,
  pay_cents integer not null check (pay_cents > 0),
  deadline date,
  brief text not null default '',
  status text not null default 'draft' check (status in ('draft', 'locked')),
  locked_at timestamptz,
  created_at timestamptz not null default now()
);

create table tasks (
  id uuid primary key default gen_random_uuid(),
  iteration_id uuid not null references iterations(id) on delete cascade,
  title text not null,
  description text not null default '',
  review text not null default 'open' check (review in ('open', 'needs_revision')),
  status text not null default 'open' check (status in ('open', 'under_review', 'revision_needed', 'complete')),
  share_bps integer check (share_bps is null or (share_bps >= 0 and share_bps <= 10000)),
  proof_summary text not null default '',
  proof_url text not null default '',
  created_at timestamptz not null default now()
);

create table task_assignees (
  task_id uuid not null references tasks(id) on delete cascade,
  person_id uuid not null references people(id),
  primary key (task_id, person_id)
);

create table task_links (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id) on delete cascade,
  url text not null,
  label text not null default ''
);

create table task_files (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id) on delete cascade,
  path text not null,
  filename text not null
);

create table subtasks (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id) on delete cascade,
  title text not null,
  description text not null default '',
  effort numeric not null default 1 check (effort > 0),
  value numeric not null default 1 check (value >= 0),
  embedding vector(768),
  search_text tsvector generated always as (
    to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, ''))
  ) stored,
  created_at timestamptz not null default now()
);

create index subtasks_search_idx on subtasks using gin (search_text);

create table subtask_links (
  id uuid primary key default gen_random_uuid(),
  subtask_id uuid not null references subtasks(id) on delete cascade,
  url text not null,
  label text not null default ''
);

create table subtask_files (
  id uuid primary key default gen_random_uuid(),
  subtask_id uuid not null references subtasks(id) on delete cascade,
  path text not null,
  filename text not null
);

create table completions (
  id uuid primary key default gen_random_uuid(),
  subtask_id uuid not null references subtasks(id) on delete cascade,
  summary text not null default '',
  model_outcome text check (model_outcome in ('credit', 'dispute')),
  model_reason text,
  created_at timestamptz not null default now()
);

create table completion_links (
  id uuid primary key default gen_random_uuid(),
  completion_id uuid not null references completions(id) on delete cascade,
  url text not null,
  label text not null default ''
);

create table completion_files (
  id uuid primary key default gen_random_uuid(),
  completion_id uuid not null references completions(id) on delete cascade,
  path text not null,
  filename text not null
);

create table decisions (
  id uuid primary key default gen_random_uuid(),
  completion_id uuid not null references completions(id) on delete cascade,
  approver_id uuid not null references people(id),
  outcome text not null check (outcome in ('credit', 'dispute')),
  note text not null default '',
  created_at timestamptz not null default now()
);

insert into people (id, name, role) values
  ('11111111-1111-4111-8111-111111111111', 'Cool Client', 'client'),
  ('22222222-2222-4222-8222-222222222222', 'Worker One', 'worker'),
  ('33333333-3333-4333-8333-333333333333', 'Worker Dos', 'worker')
on conflict (id) do nothing;

insert into projects (id, client_id, worker_id, title, description) values
  (
    '44444444-4444-4444-8444-444444444441',
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    'Northwind portal',
    'The signed-in order desk for Northwind Goods.'
  ),
  (
    '44444444-4444-4444-8444-444444444442',
    '11111111-1111-4111-8111-111111111111',
    '33333333-3333-4333-8333-333333333333',
    'Field notes',
    'Photo notes from the loading dock, for the same client.'
  );

insert into iterations (id, project_id, title, pay_cents, deadline, brief, status, locked_at) values
  (
    '55555555-5555-4555-8555-555555555551',
    '44444444-4444-4444-8444-444444444441',
    'Cycle 1',
    400000,
    '2026-10-31',
    'Ship the order list, packed status, and the Monday summary.',
    'locked',
    now()
  ),
  (
    '55555555-5555-4555-8555-555555555552',
    '44444444-4444-4444-8444-444444444441',
    'Cycle 2',
    250000,
    '2026-11-14',
    'Add a returns queue and a note the warehouse can read on each return.',
    'draft',
    null
  ),
  (
    '55555555-5555-4555-8555-555555555553',
    '44444444-4444-4444-8444-444444444442',
    'Cycle 1',
    80000,
    null,
    'Photograph the dock and write the short caption.',
    'draft',
    null
  );

insert into tasks (id, iteration_id, title, description) values
  (
    '66666666-6666-4666-8666-666666666661',
    '55555555-5555-4555-8555-555555555551',
    'Client order list',
    'A signed-in list of this client''s orders, with a way to mark one packed.'
  ),
  (
    '66666666-6666-4666-8666-666666666662',
    '55555555-5555-4555-8555-555555555551',
    'Weekly summary',
    'A short email of orders packed that week.'
  ),
  (
    '66666666-6666-4666-8666-666666666663',
    '55555555-5555-4555-8555-555555555553',
    'Dock photos',
    'Pictures and a caption from the loading dock.'
  );

insert into task_assignees (task_id, person_id) values
  ('66666666-6666-4666-8666-666666666661', '22222222-2222-4222-8222-222222222222'),
  ('66666666-6666-4666-8666-666666666661', '33333333-3333-4333-8333-333333333333'),
  ('66666666-6666-4666-8666-666666666662', '22222222-2222-4222-8222-222222222222');

insert into subtasks (id, task_id, title, description, effort, value) values
  (
    '77777777-7777-4777-8777-777777777771',
    '66666666-6666-4666-8666-666666666661',
    'Signed-in order list',
    'Show only this client''s orders after sign-in.',
    2, 4
  ),
  (
    '77777777-7777-4777-8777-777777777772',
    '66666666-6666-4666-8666-666666666661',
    'Mark an order packed',
    'Each order row has a control that sets the status to packed and refreshes the list.',
    1, 5
  ),
  (
    '77777777-7777-4777-8777-777777777773',
    '66666666-6666-4666-8666-666666666662',
    'Monday email',
    'Send one email each Monday listing the orders packed in the previous week.',
    2, 3
  ),
  (
    '77777777-7777-4777-8777-777777777774',
    '66666666-6666-4666-8666-666666666663',
    'Photograph the dock',
    'Three photos of the loading dock, with a one-line caption.',
    1, 2
  );

insert into completions (id, subtask_id, summary, model_outcome, model_reason) values
  (
    '88888888-8888-4888-8888-888888888881',
    '77777777-7777-4777-8777-777777777772',
    'Each order row has a packed control. The list refreshes after it is used.',
    'credit',
    'The proof shows a packed control on each order row and a refresh, which is what the description asks for.'
  ),
  (
    '88888888-8888-4888-8888-888888888882',
    '77777777-7777-4777-8777-777777777773',
    'Draft of the Monday email is written. It has not been sent.',
    null,
    null
  );

insert into completion_links (completion_id, url, label) values
  ('88888888-8888-4888-8888-888888888881', 'https://example.com/northwind/orders', 'Order list');

insert into decisions (completion_id, approver_id, outcome, note) values
  (
    '88888888-8888-4888-8888-888888888881',
    '11111111-1111-4111-8111-111111111111',
    'credit',
    ''
  );
