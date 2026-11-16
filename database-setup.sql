-- Apna Sajhedari: secure shared database (Supabase / PostgreSQL)
-- Run this file once in Supabase SQL Editor. Do NOT put service-role keys in index.html.

create extension if not exists pgcrypto;

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin','member')),
  display_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  member_code text not null unique,
  full_name text not null,
  mobile text,
  note text,
  photo_url text,
  document_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.cash_transactions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('deposit','withdrawal','profit','loss')),
  amount numeric(14,2) not null check (amount > 0),
  transaction_date date not null default current_date,
  reference_note text,
  status text not null default 'approved' check (status in ('pending','approved','rejected')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.company_entries (
  id uuid primary key default gen_random_uuid(),
  entry_type text not null check (entry_type in ('income','expense')),
  amount numeric(14,2) not null check (amount > 0),
  entry_date date not null default current_date,
  category text,
  description text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.company_daily_results (
  id uuid primary key default gen_random_uuid(),
  result_date date not null unique,
  net_result numeric(14,2) not null,
  note text,
  approved boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin'
  );
$$;

alter table public.user_profiles enable row level security;
alter table public.members enable row level security;
alter table public.cash_transactions enable row level security;
alter table public.company_entries enable row level security;
alter table public.company_daily_results enable row level security;

drop policy if exists "profile self or admin read" on public.user_profiles;
create policy "profile self or admin read" on public.user_profiles
for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists "admin manages profiles" on public.user_profiles;
create policy "admin manages profiles" on public.user_profiles
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "member sees own member row or admin sees all" on public.members;
create policy "member sees own member row or admin sees all" on public.members
for select to authenticated
using (auth_user_id = auth.uid() or public.is_admin());

drop policy if exists "admin manages members" on public.members;
create policy "admin manages members" on public.members
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "member sees own transactions or admin sees all" on public.cash_transactions;
create policy "member sees own transactions or admin sees all" on public.cash_transactions
for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1 from public.members m
    where m.id = cash_transactions.member_id and m.auth_user_id = auth.uid()
  )
);

drop policy if exists "admin manages cash transactions" on public.cash_transactions;
create policy "admin manages cash transactions" on public.cash_transactions
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin manages company entries" on public.company_entries;
create policy "admin manages company entries" on public.company_entries
for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin manages daily results" on public.company_daily_results;
create policy "admin manages daily results" on public.company_daily_results
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- IMPORTANT:
-- 1) Create the first Auth user in Supabase Authentication.
-- 2) Insert that user's UUID into user_profiles with role='admin'.
-- 3) Add members as Auth users and link their UUID in members.auth_user_id.
-- 4) Never expose a Supabase service_role key in the public website.
-- 5) Members can SELECT only their own member row and transactions; all writes are admin-only.
