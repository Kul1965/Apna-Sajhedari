-- Apna Sajhedari: Recipes, Ration Store and Purchase module
-- Additive migration: does not alter existing food/member/order tables.
create table if not exists public.food_recipes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'General',
  ingredients text not null default '',
  instructions text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.ration_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  unit text not null default 'kg',
  quantity numeric(12,3) not null default 0 check (quantity >= 0),
  reorder_level numeric(12,3) not null default 0 check (reorder_level >= 0),
  updated_at timestamptz not null default now()
);
create table if not exists public.ration_purchases (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.ration_items(id) on delete restrict,
  purchase_date date not null default current_date,
  quantity numeric(12,3) not null check (quantity > 0),
  unit_price numeric(12,2) not null default 0 check (unit_price >= 0),
  supplier text not null default '',
  notes text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.food_recipes enable row level security;
alter table public.ration_items enable row level security;
alter table public.ration_purchases enable row level security;
drop policy if exists "authenticated can read recipes" on public.food_recipes;
create policy "authenticated can read recipes" on public.food_recipes for select to authenticated using (true);
drop policy if exists "food admins manage recipes" on public.food_recipes;
create policy "food admins manage recipes" on public.food_recipes for all to authenticated
using (exists(select 1 from public.food_admins a where a.user_id=auth.uid()))
with check (exists(select 1 from public.food_admins a where a.user_id=auth.uid()));
drop policy if exists "food admins manage ration items" on public.ration_items;
create policy "food admins manage ration items" on public.ration_items for all to authenticated
using (exists(select 1 from public.food_admins a where a.user_id=auth.uid()))
with check (exists(select 1 from public.food_admins a where a.user_id=auth.uid()));
drop policy if exists "food admins manage ration purchases" on public.ration_purchases;
create policy "food admins manage ration purchases" on public.ration_purchases for all to authenticated
using (exists(select 1 from public.food_admins a where a.user_id=auth.uid()))
with check (exists(select 1 from public.food_admins a where a.user_id=auth.uid()));

-- Explicit API privileges for the authenticated admin workspace.
grant select, insert, update, delete on public.ration_items to authenticated;
grant select, insert, update, delete on public.ration_purchases to authenticated;
-- Refresh PostgREST's schema cache after the migration is applied.
notify pgrst, 'reload schema';
