-- Apna Sajhedari: secure per-admin cloud backup/sync
create table if not exists public.app_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_state enable row level security;

drop policy if exists "Admins can read own app state" on public.app_state;
create policy "Admins can read own app state"
on public.app_state for select to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1 from public.user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

drop policy if exists "Admins can insert own app state" on public.app_state;
create policy "Admins can insert own app state"
on public.app_state for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

drop policy if exists "Admins can update own app state" on public.app_state;
create policy "Admins can update own app state"
on public.app_state for update to authenticated
using (
  user_id = auth.uid()
  and exists (
    select 1 from public.user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
)
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  )
);

-- Allow signed-in users to reach the table; row-level security above
-- still restricts access to the signed-in admin's own row.
grant select, insert, update on table public.app_state to authenticated;
