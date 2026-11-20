-- Apna Sajhedari: secure Farm / Tempo worker login and own statements
-- Safe additive migration: does not alter or delete existing worker or member records.

create table if not exists public.worker_accounts (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  worker_type text not null check (worker_type in ('farm','staff','tempo')),
  worker_id text not null,
  display_name text not null,
  mobile text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(worker_type, worker_id),
  unique(auth_user_id, worker_type, worker_id)
);

alter table public.worker_accounts drop constraint if exists worker_accounts_worker_type_check;
alter table public.worker_accounts add constraint worker_accounts_worker_type_check check (worker_type in ('farm','staff','tempo'));

alter table public.worker_accounts enable row level security;
drop policy if exists "worker reads own account or admin reads all" on public.worker_accounts;
create policy "worker reads own account or admin reads all"
on public.worker_accounts for select to authenticated
using (auth_user_id = auth.uid() or public.is_admin());

grant select on public.worker_accounts to authenticated;

create index if not exists idx_worker_accounts_auth_user on public.worker_accounts(auth_user_id);
create index if not exists idx_worker_accounts_mobile on public.worker_accounts(mobile);

create or replace function public.get_my_worker_statements()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_state jsonb;
  v_result jsonb;
begin
  if v_uid is null then raise exception 'Please login first.'; end if;

  select a.data into v_state
  from public.app_state a
  join public.user_profiles p on p.user_id = a.user_id and p.role = 'admin'
  order by a.updated_at desc
  limit 1;

  if v_state is null then
    raise exception 'Admin ka latest cloud backup abhi uplabdh nahi hai.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'account_id', wa.id,
    'worker_type', wa.worker_type,
    'worker_id', wa.worker_id,
    'name', wa.display_name,
    'mobile', wa.mobile,
    'worker', case when wa.worker_type in ('farm','staff')
      then (select x from jsonb_array_elements(coalesce(v_state->'staffWorkers','[]'::jsonb)) x where x->>'id'=wa.worker_id limit 1)
      else (select x from jsonb_array_elements(coalesce(v_state->'tempo'->'workers','[]'::jsonb)) x where x->>'id'=wa.worker_id limit 1)
    end,
    'duties', case when wa.worker_type = 'farm'
      then (select coalesce(jsonb_agg(x),'[]'::jsonb) from jsonb_array_elements(coalesce(v_state->'staffWork','[]'::jsonb)) x where x->>'workerId'=wa.worker_id)
      else (select coalesce(jsonb_agg(x),'[]'::jsonb) from jsonb_array_elements(coalesce(v_state->'tempo'->'duties','[]'::jsonb)) x where x->>'workerId'=wa.worker_id)
    end,
    'payments', case when wa.worker_type = 'farm'
      then (select coalesce(jsonb_agg(x),'[]'::jsonb) from jsonb_array_elements(coalesce(v_state->'staffPayments','[]'::jsonb)) x where x->>'workerId'=wa.worker_id)
      else (select coalesce(jsonb_agg(x),'[]'::jsonb) from jsonb_array_elements(coalesce(v_state->'tempo'->'payments','[]'::jsonb)) x where x->>'workerId'=wa.worker_id)
    end
  )), '[]'::jsonb) into v_result
  from public.worker_accounts wa
  where wa.auth_user_id = v_uid and wa.active = true;

  if jsonb_array_length(v_result)=0 then
    raise exception 'Is login se koi active Farm ya Tempo Worker record link nahi hai.';
  end if;
  return v_result;
end;
$$;

revoke all on function public.get_my_worker_statements() from public;
grant execute on function public.get_my_worker_statements() to authenticated;
