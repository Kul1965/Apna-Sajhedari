-- Add ration issue/withdrawal records. Existing stock and purchase history remain untouched.
create table if not exists public.ration_issues (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.ration_items(id) on delete restrict,
  issue_date date not null default current_date,
  recipient text not null,
  quantity numeric(12,3) not null check (quantity > 0),
  notes text not null default '',
  issued_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.ration_issues enable row level security;
drop policy if exists "food admins manage ration issues" on public.ration_issues;
create policy "food admins manage ration issues" on public.ration_issues for all to authenticated
using (exists(select 1 from public.food_admins a where a.user_id=auth.uid()))
with check (exists(select 1 from public.food_admins a where a.user_id=auth.uid()));
grant select, insert, update, delete on public.ration_issues to authenticated;
notify pgrst, 'reload schema';
