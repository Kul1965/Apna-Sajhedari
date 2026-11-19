-- Apna Sajhedari: secure two-way replies for Admin and Members
-- Run this file once in Supabase SQL Editor.

create table if not exists public.member_message_replies (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.member_messages(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_role text not null check (sender_role in ('admin','member')),
  body text not null check (length(trim(body)) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists member_message_replies_message_created_idx
  on public.member_message_replies(message_id, created_at);

alter table public.member_message_replies enable row level security;

drop policy if exists "admin reads all message replies" on public.member_message_replies;
create policy "admin reads all message replies"
on public.member_message_replies
for select to authenticated
using (public.is_admin());

drop policy if exists "members read replies in their inbox" on public.member_message_replies;
create policy "members read replies in their inbox"
on public.member_message_replies
for select to authenticated
using (
  exists (
    select 1
    from public.members m
    join public.member_messages mm on mm.id = member_message_replies.message_id
    where m.auth_user_id = auth.uid()
      and m.active = true
      and mm.active = true
      and (mm.target_member_id is null or mm.target_member_id = m.id)
  )
);

drop policy if exists "admin or inbox member sends replies" on public.member_message_replies;
create policy "admin or inbox member sends replies"
on public.member_message_replies
for insert to authenticated
with check (
  (
    sender_id = auth.uid()
    and sender_role = 'admin'
    and public.is_admin()
  )
  or
  (
    sender_id = auth.uid()
    and sender_role = 'member'
    and exists (
      select 1
      from public.members m
      join public.member_messages mm on mm.id = member_message_replies.message_id
      where m.auth_user_id = auth.uid()
        and m.active = true
        and mm.active = true
        and (mm.target_member_id is null or mm.target_member_id = m.id)
    )
  )
);

grant select, insert on public.member_message_replies to authenticated;
