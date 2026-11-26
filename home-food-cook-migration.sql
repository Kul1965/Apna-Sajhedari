-- Home Made Food cook role migration. Run after home-food-database.sql.
create table if not exists public.food_cooks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.food_cooks enable row level security;

create or replace function public.is_food_cook()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.food_cooks where user_id=auth.uid() and active); $$;
revoke all on function public.is_food_cook() from public;
grant execute on function public.is_food_cook() to authenticated;

drop policy if exists food_cooks_self_read on public.food_cooks;
create policy food_cooks_self_read on public.food_cooks for select to authenticated using (user_id=auth.uid() or public.is_food_admin());
drop policy if exists food_cooks_admin_manage on public.food_cooks;
create policy food_cooks_admin_manage on public.food_cooks for all to authenticated using (public.is_food_admin()) with check (public.is_food_admin());

drop policy if exists food_orders_customer_admin_read on public.food_orders;
create policy food_orders_customer_admin_read on public.food_orders for select to authenticated
using (customer_user_id=auth.uid() or public.is_food_admin() or public.is_food_cook());
drop policy if exists food_orders_cook_update on public.food_orders;
create policy food_orders_cook_update on public.food_orders for update to authenticated
using (public.is_food_cook() and status in ('pending','accepted','preparing'))
with check (public.is_food_cook() and status in ('accepted','preparing','ready'));
grant select on public.food_cooks to authenticated;
grant update on public.food_orders to authenticated;

drop policy if exists food_order_items_read on public.food_order_items;
create policy food_order_items_read on public.food_order_items for select to authenticated
using (public.is_food_admin() or public.is_food_cook() or exists (select 1 from public.food_orders o where o.id=order_id and o.customer_user_id=auth.uid()));
