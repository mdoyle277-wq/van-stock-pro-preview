-- Van Stock Pro PREVIEW database bootstrap
-- Run ONLY in the dedicated preview Supabase project.
-- Safe for a new/empty project: creates missing objects; does not drop or truncate data.

create extension if not exists pgcrypto;

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Van Stock Pro',
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member','viewer')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists public.stock_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  legacy_id text not null,
  name text not null default 'Unnamed item',
  sku text not null default '',
  barcode text not null default '',
  category text not null default '',
  qty numeric not null default 0,
  min_qty numeric not null default 0,
  max_qty numeric,
  location text not null default '',
  supplier text not null default '',
  supplier_url text not null default '',
  notes text not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, owner_user_id, legacy_id)
);

create index if not exists stock_items_workspace_owner_idx
  on public.stock_items (workspace_id, owner_user_id);

create table if not exists public.job_usage_records (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  usage_date timestamptz not null default now(),
  job_reference text not null,
  item_id text not null default '',
  item_name text not null default 'Unnamed item',
  sku text not null default '',
  category text not null default '',
  quantity integer not null check (quantity > 0),
  engineer_name text not null default '',
  visit_notes text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists job_usage_owner_date_idx
  on public.job_usage_records (workspace_id, owner_user_id, usage_date desc);

create table if not exists public.job_site_visits (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  visit_date timestamptz not null default now(),
  job_reference text not null,
  site_name text not null default '',
  engineer_name text not null default '',
  system_type text not null default '',
  visit_notes text not null default '',
  defects text not null default '',
  follow_up text not null default '',
  battery_type text not null default '',
  battery_quantity numeric,
  battery_installed_date date,
  battery_due_date date,
  intruder_battery_type text not null default '',
  intruder_battery_other text not null default '',
  intruder_battery_quantity numeric,
  intruder_battery_installed_date date,
  intruder_battery_due_date date,
  created_at timestamptz not null default now()
);

create index if not exists job_site_visits_owner_date_idx
  on public.job_site_visits (workspace_id, owner_user_id, visit_date desc);

-- Job/site master records for the planned job-first workflow.
create table if not exists public.job_records (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  job_reference text not null,
  site_name text not null default '',
  customer_name text not null default '',
  site_address text not null default '',
  engineer_name text not null default '',
  job_status text not null default 'Open' check (job_status in ('Open','In progress','Completed','On hold')),
  job_notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, owner_user_id, job_reference)
);

create index if not exists job_records_owner_status_idx
  on public.job_records (workspace_id, owner_user_id, job_status, updated_at desc);

-- SECURITY DEFINER helpers avoid recursive RLS lookups on workspace_members.
create or replace function public.is_workspace_member(target_workspace uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.workspace_members wm
    where wm.workspace_id = target_workspace and wm.user_id = auth.uid()
  );
$$;

create or replace function public.is_workspace_creator(target_workspace uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.workspaces w
    where w.id = target_workspace and w.created_by = auth.uid()
  );
$$;

create or replace function public.has_workspace_role(target_workspace uuid, allowed_roles text[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.workspace_members wm
    where wm.workspace_id = target_workspace
      and wm.user_id = auth.uid()
      and wm.role = any(allowed_roles)
  );
$$;

alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.stock_items enable row level security;
alter table public.job_usage_records enable row level security;
alter table public.job_site_visits enable row level security;
alter table public.job_records enable row level security;

drop policy if exists "preview_workspace_select" on public.workspaces;
create policy "preview_workspace_select" on public.workspaces
for select to authenticated
using (public.is_workspace_member(id) or created_by = auth.uid());

drop policy if exists "preview_workspace_insert" on public.workspaces;
create policy "preview_workspace_insert" on public.workspaces
for insert to authenticated
with check (created_by = auth.uid());

drop policy if exists "preview_workspace_update" on public.workspaces;
create policy "preview_workspace_update" on public.workspaces
for update to authenticated
using (public.has_workspace_role(id, array['owner','admin']))
with check (public.has_workspace_role(id, array['owner','admin']));

drop policy if exists "preview_members_select" on public.workspace_members;
create policy "preview_members_select" on public.workspace_members
for select to authenticated
using (user_id = auth.uid() or public.is_workspace_member(workspace_id)
       or public.is_workspace_creator(workspace_id));

drop policy if exists "preview_members_insert" on public.workspace_members;
create policy "preview_members_insert" on public.workspace_members
for insert to authenticated
with check (
  (user_id = auth.uid() and role = 'owner' and public.is_workspace_creator(workspace_id))
  or public.has_workspace_role(workspace_id, array['owner','admin'])
);

drop policy if exists "preview_members_delete" on public.workspace_members;
create policy "preview_members_delete" on public.workspace_members
for delete to authenticated
using (public.has_workspace_role(workspace_id, array['owner','admin'])
       and user_id <> auth.uid());

drop policy if exists "preview_stock_select" on public.stock_items;
create policy "preview_stock_select" on public.stock_items
for select to authenticated
using (owner_user_id = auth.uid() and public.is_workspace_member(workspace_id));

drop policy if exists "preview_stock_insert" on public.stock_items;
create policy "preview_stock_insert" on public.stock_items
for insert to authenticated
with check (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_stock_update" on public.stock_items;
create policy "preview_stock_update" on public.stock_items
for update to authenticated
using (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']))
with check (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_stock_delete" on public.stock_items;
create policy "preview_stock_delete" on public.stock_items
for delete to authenticated
using (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_usage_select" on public.job_usage_records;
create policy "preview_usage_select" on public.job_usage_records
for select to authenticated
using (owner_user_id = auth.uid() and public.is_workspace_member(workspace_id));

drop policy if exists "preview_usage_insert" on public.job_usage_records;
create policy "preview_usage_insert" on public.job_usage_records
for insert to authenticated
with check (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_usage_delete" on public.job_usage_records;
create policy "preview_usage_delete" on public.job_usage_records
for delete to authenticated
using (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_visits_select" on public.job_site_visits;
create policy "preview_visits_select" on public.job_site_visits
for select to authenticated
using (owner_user_id = auth.uid() and public.is_workspace_member(workspace_id));

drop policy if exists "preview_visits_insert" on public.job_site_visits;
create policy "preview_visits_insert" on public.job_site_visits
for insert to authenticated
with check (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_visits_delete" on public.job_site_visits;
create policy "preview_visits_delete" on public.job_site_visits
for delete to authenticated
using (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_jobs_select" on public.job_records;
create policy "preview_jobs_select" on public.job_records
for select to authenticated
using (owner_user_id = auth.uid() and public.is_workspace_member(workspace_id));

drop policy if exists "preview_jobs_insert" on public.job_records;
create policy "preview_jobs_insert" on public.job_records
for insert to authenticated
with check (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_jobs_update" on public.job_records;
create policy "preview_jobs_update" on public.job_records
for update to authenticated
using (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']))
with check (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin','member']));

drop policy if exists "preview_jobs_delete" on public.job_records;
create policy "preview_jobs_delete" on public.job_records
for delete to authenticated
using (owner_user_id = auth.uid() and public.has_workspace_role(workspace_id, array['owner','admin']));

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.workspaces, public.workspace_members,
  public.stock_items, public.job_usage_records, public.job_site_visits, public.job_records to authenticated;
grant execute on function public.is_workspace_member(uuid) to authenticated;
grant execute on function public.is_workspace_creator(uuid) to authenticated;
grant execute on function public.has_workspace_role(uuid, text[]) to authenticated;

-- End of preview-only bootstrap. No production project is referenced here.
