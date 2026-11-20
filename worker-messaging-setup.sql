-- Apna Sajhedari: private two-way messaging for Farm / Tempo staff
-- Additive only. Existing member conversations and records are untouched.

create table if not exists public.worker_messages (
  id uuid primary key default gen_random_uuid(),
  worker_account_id uuid not null references public.worker_accounts(id) on delete cascade,
  sender_user_id uuid not null references auth.users(id) on delete cascade,
  sender_role text not null check (sender_role in ('admin','worker')),
  body text not null check (length(trim(body)) between 1 and 5000),
  created_at timestamptz not null default now(),
  read_by_admin boolean not null default false,
  read_by_worker boolean not null default false
);

create index if not exists idx_worker_messages_account_time
  on public.worker_messages(worker_account_id, created_at);

alter table public.worker_messages enable row level security;
revoke all on public.worker_messages from anon, authenticated;
grant select, insert, update, delete on public.worker_messages to service_role;

create or replace function public.admin_get_worker_messages_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null or not public.is_admin() then
    raise exception 'Only Admin can view staff conversations.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'account_id', wa.id,
    'worker_type', wa.worker_type,
    'worker_id', wa.worker_id,
    'display_name', wa.display_name,
    'mobile', wa.mobile,
    'auth_user_id', wa.auth_user_id,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', wm.id, 'sender_user_id', wm.sender_user_id,
        'sender_role', wm.sender_role, 'body', wm.body,
        'created_at', wm.created_at
      ) order by wm.created_at)
      from public.worker_messages wm
      where wm.worker_account_id = wa.id
    ), '[]'::jsonb)
  ) order by wa.display_name), '[]'::jsonb)
  into v_result
  from public.worker_accounts wa
  where wa.active = true;
  return v_result;
end;
$$;

create or replace function public.admin_send_worker_message_v1(p_worker_account_id uuid, p_body text)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null or not public.is_admin() then
    raise exception 'Only Admin can message staff.';
  end if;
  if length(trim(coalesce(p_body,''))) not between 1 and 5000 then
    raise exception 'Message must be 1 to 5000 characters.';
  end if;
  if not exists(select 1 from public.worker_accounts where id=p_worker_account_id and active=true) then
    raise exception 'Active staff account not found.';
  end if;
  insert into public.worker_messages(worker_account_id,sender_user_id,sender_role,body)
  values(p_worker_account_id,v_uid,'admin',trim(p_body))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.get_my_worker_messages_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null then raise exception 'Please login first.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'account_id', wa.id,
    'worker_type', wa.worker_type,
    'display_name', wa.display_name,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', wm.id, 'sender_role', wm.sender_role,
        'body', wm.body, 'created_at', wm.created_at
      ) order by wm.created_at)
      from public.worker_messages wm
      where wm.worker_account_id = wa.id
    ), '[]'::jsonb)
  )), '[]'::jsonb) into v_result
  from public.worker_accounts wa
  where wa.auth_user_id=v_uid and wa.active=true;
  return v_result;
end;
$$;

create or replace function public.worker_send_message_v1(p_body text)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_uid uuid := auth.uid(); v_account uuid; v_id uuid;
begin
  if v_uid is null then raise exception 'Please login first.'; end if;
  if length(trim(coalesce(p_body,''))) not between 1 and 5000 then
    raise exception 'Message must be 1 to 5000 characters.';
  end if;
  select id into v_account from public.worker_accounts
  where auth_user_id=v_uid and active=true
  order by created_at limit 1;
  if v_account is null then raise exception 'Active staff account not found.'; end if;
  insert into public.worker_messages(worker_account_id,sender_user_id,sender_role,body)
  values(v_account,v_uid,'worker',trim(p_body))
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.admin_get_worker_messages_v1() from public;
revoke all on function public.admin_send_worker_message_v1(uuid,text) from public;
revoke all on function public.get_my_worker_messages_v1() from public;
revoke all on function public.worker_send_message_v1(text) from public;
grant execute on function public.admin_get_worker_messages_v1() to authenticated;
grant execute on function public.admin_send_worker_message_v1(uuid,text) to authenticated;
grant execute on function public.get_my_worker_messages_v1() to authenticated;
grant execute on function public.worker_send_message_v1(text) to authenticated;
