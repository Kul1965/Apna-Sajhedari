-- Apna Sajhedari: secure access upgrade (run AFTER database-setup.sql)
-- Safe to run more than once. This does not delete existing tables or records.
-- Never put the Supabase service_role key in the website.

-- Members may submit deposit/withdrawal requests. Requests remain pending until Admin approves.
drop policy if exists "member submits own pending cash request" on public.cash_transactions;
create policy "member submits own pending cash request" on public.cash_transactions
for insert to authenticated
with check (
  created_by = auth.uid()
  and status = 'pending'
  and transaction_type in ('deposit','withdrawal')
  and exists (
    select 1 from public.members m
    where m.id = cash_transactions.member_id
      and m.auth_user_id = auth.uid()
      and m.active = true
  )
);

-- Members may see approved daily company results for the live profit/loss summary.
drop policy if exists "authenticated reads approved daily results" on public.company_daily_results;
create policy "authenticated reads approved daily results" on public.company_daily_results
for select to authenticated
using (approved = true or public.is_admin());

-- Explicit minimum table privileges for the authenticated app.
grant usage on schema public to authenticated;
grant select on public.user_profiles to authenticated;
grant select on public.members to authenticated;
grant select on public.cash_transactions to authenticated;
grant insert on public.cash_transactions to authenticated;
grant select on public.company_daily_results to authenticated;
grant select, insert, update, delete on public.company_entries to authenticated;
grant select, insert, update, delete on public.members to authenticated;
grant select, insert, update, delete on public.user_profiles to authenticated;
grant select, insert, update, delete on public.company_daily_results to authenticated;
grant select, insert, update, delete on public.cash_transactions to authenticated;

create index if not exists idx_members_auth_user_id on public.members(auth_user_id);
create index if not exists idx_cash_transactions_member_date on public.cash_transactions(member_id, transaction_date desc);
create index if not exists idx_company_daily_results_date on public.company_daily_results(result_date desc);

-- ADMIN SETUP (do this after creating the first user in Supabase Authentication):
-- 1) Open Authentication > Users and copy the first admin user's UUID.
-- 2) Run the following after replacing YOUR-ADMIN-USER-UUID:
-- insert into public.user_profiles(user_id, role, display_name)
-- values ('YOUR-ADMIN-USER-UUID', 'admin', 'Apna Sajhedari Admin')
-- on conflict (user_id) do update set role='admin', display_name=excluded.display_name;
--
-- Each member must also have an Auth user. Link that user's UUID to the member row
-- in members.auth_user_id. Do not share admin credentials with members.
