-- Customer/admin messenger for Babita Food Cart.
-- Additive migration: creates new messaging tables only; existing orders/recipes are untouched.

create table if not exists public.food_message_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  avatar_url text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.food_conversations (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.food_conversation_participants (
  conversation_id uuid not null references public.food_conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);

create table if not exists public.food_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.food_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 5000),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);

create index if not exists idx_food_conversations_updated on public.food_conversations(updated_at desc);
create index if not exists idx_food_participants_user on public.food_conversation_participants(user_id, conversation_id);
create index if not exists idx_food_messages_conversation_time on public.food_messages(conversation_id, created_at desc);
create index if not exists idx_food_messages_sender on public.food_messages(sender_id, created_at desc);

alter table public.food_message_profiles enable row level security;
alter table public.food_conversations enable row level security;
alter table public.food_conversation_participants enable row level security;
alter table public.food_messages enable row level security;

drop policy if exists "food message profiles readable by signed-in users" on public.food_message_profiles;
create policy "food message profiles readable by signed-in users"
  on public.food_message_profiles for select to authenticated using (true);
drop policy if exists "users manage own food message profile" on public.food_message_profiles;
create policy "users manage own food message profile"
  on public.food_message_profiles for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "users update own food message profile" on public.food_message_profiles;
create policy "users update own food message profile"
  on public.food_message_profiles for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "participants and food admins read conversations" on public.food_conversations;
create policy "participants and food admins read conversations"
  on public.food_conversations for select to authenticated
  using (
    exists (select 1 from public.food_conversation_participants p where p.conversation_id = id and p.user_id = auth.uid())
    or exists (select 1 from public.food_admins a where a.user_id = auth.uid())
  );
drop policy if exists "signed-in users create conversations" on public.food_conversations;
create policy "signed-in users create conversations"
  on public.food_conversations for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "participants and food admins update conversations" on public.food_conversations;
create policy "participants and food admins update conversations"
  on public.food_conversations for update to authenticated
  using (
    exists (select 1 from public.food_conversation_participants p where p.conversation_id = id and p.user_id = auth.uid())
    or exists (select 1 from public.food_admins a where a.user_id = auth.uid())
  )
  with check (
    exists (select 1 from public.food_conversation_participants p where p.conversation_id = id and p.user_id = auth.uid())
    or exists (select 1 from public.food_admins a where a.user_id = auth.uid())
  );

drop policy if exists "participants and food admins read participant list" on public.food_conversation_participants;
create policy "participants and food admins read participant list"
  on public.food_conversation_participants for select to authenticated
  using (
    exists (select 1 from public.food_conversation_participants me where me.conversation_id = conversation_id and me.user_id = auth.uid())
    or exists (select 1 from public.food_admins a where a.user_id = auth.uid())
  );
drop policy if exists "conversation creator or food admin adds participants" on public.food_conversation_participants;
create policy "conversation creator or food admin adds participants"
  on public.food_conversation_participants for insert to authenticated
  with check (
    exists (select 1 from public.food_conversations c where c.id = conversation_id and c.created_by = auth.uid())
    or exists (select 1 from public.food_admins a where a.user_id = auth.uid())
  );
drop policy if exists "users update own participant read marker" on public.food_conversation_participants;
create policy "users update own participant read marker"
  on public.food_conversation_participants for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "participants and food admins read messages" on public.food_messages;
create policy "participants and food admins read messages"
  on public.food_messages for select to authenticated
  using (
    exists (select 1 from public.food_conversation_participants p where p.conversation_id = food_messages.conversation_id and p.user_id = auth.uid())
    or exists (select 1 from public.food_admins a where a.user_id = auth.uid())
  );
drop policy if exists "participants and food admins send messages" on public.food_messages;
create policy "participants and food admins send messages"
  on public.food_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (
      exists (select 1 from public.food_conversation_participants p where p.conversation_id = food_messages.conversation_id and p.user_id = auth.uid())
      or exists (select 1 from public.food_admins a where a.user_id = auth.uid())
    )
  );
drop policy if exists "sender or food admin edits messages" on public.food_messages;
create policy "sender or food admin edits messages"
  on public.food_messages for update to authenticated
  using (sender_id = auth.uid() or exists (select 1 from public.food_admins a where a.user_id = auth.uid()))
  with check (sender_id = auth.uid() or exists (select 1 from public.food_admins a where a.user_id = auth.uid()));

grant select, insert, update on public.food_message_profiles to authenticated;
grant select, insert, update on public.food_conversations to authenticated;
grant select, insert, update on public.food_conversation_participants to authenticated;
grant select, insert, update on public.food_messages to authenticated;

notify pgrst, 'reload schema';
