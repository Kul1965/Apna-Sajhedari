-- Apna Sajhedari: Admin notices/offers and private member inbox
-- Run once in Supabase SQL Editor. Does not change existing member or financial records.

create table if not exists public.member_messages (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  message_type text not null default 'notice'
    check (message_type in ('notice','offer','congratulation','personal')),
  target_member_id uuid references public.members(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  active boolean not null default true
);

create table if not exists public.member_message_reads (
  message_id uuid not null references public.member_messages(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, member_id)
);

alter table public.member_messages enable row level security;
alter table public.member_message_reads enable row level security;

drop policy if exists "admin manages member messages" on public.member_messages;
create policy "admin manages member messages"
on public.member_messages for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "members read their messages" on public.member_messages;
create policy "members read their messages"
on public.member_messages for select to authenticated
using (
  active = true and exists (
    select 1 from public.members m
    where m.auth_user_id = auth.uid()
      and m.active = true
      and (member_messages.target_member_id is null or member_messages.target_member_id = m.id)
  )
);

drop policy if exists "admin reads message receipts" on public.member_message_reads;
create policy "admin reads message receipts"
on public.member_message_reads for select to authenticated
using (public.is_admin());

drop policy if exists "member reads own receipts" on public.member_message_reads;
create policy "member reads own receipts"
on public.member_message_reads for select to authenticated
using (exists (
  select 1 from public.members m
  where m.id = member_message_reads.member_id and m.auth_user_id = auth.uid()
));

drop policy if exists "member marks own message read" on public.member_message_reads;
create policy "member marks own message read"
on public.member_message_reads for insert to authenticated
with check (exists (
  select 1 from public.members m
  where m.id = member_message_reads.member_id and m.auth_user_id = auth.uid()
));

grant select, insert, update, delete on public.member_messages to authenticated;
grant select, insert on public.member_message_reads to authenticated;

create or replace function public.get_my_member_messages()
returns table (
  id uuid,
  title text,
  body text,
  message_type text,
  created_at timestamptz,
  is_read boolean
)
language sql
security definer
set search_path = public, auth
as $$
  select mm.id, mm.title, mm.body, mm.message_type, mm.created_at,
    exists (
      select 1 from public.member_message_reads r
      where r.message_id = mm.id and r.member_id = m.id
    ) as is_read
  from public.members m
  join public.member_messages mm
    on mm.active = true
   and (mm.target_member_id is null or mm.target_member_id = m.id)
  where m.auth_user_id = auth.uid() and m.active = true
  order by mm.created_at desc;
$$;

create or replace function public.mark_my_member_message_read(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_member_id uuid;
begin
  select id into v_member_id
  from public.members
  where auth_user_id = auth.uid() and active = true;

  if v_member_id is null then
    raise exception 'Active member account not found.';
  end if;

  if not exists (
    select 1 from public.member_messages mm
    where mm.id = p_message_id and mm.active = true
      and (mm.target_member_id is null or mm.target_member_id = v_member_id)
  ) then
    raise exception 'Message not found for this member.';
  end if;

  insert into public.member_message_reads(message_id, member_id)
  values (p_message_id, v_member_id)
  on conflict (message_id, member_id) do nothing;

  return true;
end;
$$;

revoke all on function public.get_my_member_messages() from public;
revoke all on function public.mark_my_member_message_read(uuid) from public;
grant execute on function public.get_my_member_messages() to authenticated;
grant execute on function public.mark_my_member_message_read(uuid) to authenticated;
