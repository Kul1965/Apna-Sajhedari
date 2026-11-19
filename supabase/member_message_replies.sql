-- Apna Sajhedari: secure member replies for Admin messages
-- Run this once in Supabase SQL Editor. This does not alter accounting tables or existing records.

create table if not exists public.member_message_replies (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.member_messages(id) on delete cascade,
  member_user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists member_message_replies_message_created_idx
  on public.member_message_replies (message_id, created_at);

create index if not exists member_message_replies_user_created_idx
  on public.member_message_replies (member_user_id, created_at);

alter table public.member_message_replies enable row level security;

drop policy if exists "Member can read own message replies" on public.member_message_replies;
create policy "Member can read own message replies"
on public.member_message_replies
for select
to authenticated
using (member_user_id = auth.uid());

drop policy if exists "Admin can read all message replies" on public.member_message_replies;
create policy "Admin can read all message replies"
on public.member_message_replies
for select
to authenticated
using (public.is_admin());

drop policy if exists "Approved member can reply to delivered messages" on public.member_message_replies;
create policy "Approved member can reply to delivered messages"
on public.member_message_replies
for insert
to authenticated
with check (
  member_user_id = auth.uid()
  and exists (
    select 1
    from public.member_access_requests ar
    join public.member_messages mm on mm.id = member_message_replies.message_id
    where ar.auth_user_id = auth.uid()
      and ar.status = 'approved'
      and mm.active = true
      and (mm.target_member_id is null or mm.target_member_id = ar.member_id)
  )
);

grant select, insert on public.member_message_replies to authenticated;
