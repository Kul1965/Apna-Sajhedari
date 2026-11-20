-- Apna Sajhedari: secure own-member statement
-- Run in Supabase SQL Editor after member-access-approval.sql.
-- Returns only the authenticated member's own summary and capital history.
-- It never returns app_state, other members, shared ledger entries, photos, or documents.

create or replace function public.get_my_member_statement()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_member public.members%rowtype;
  v_state jsonb;
  v_members jsonb;
  v_entries jsonb;
  v_assets jsonb;
  v_liabilities jsonb;
  v_capital numeric := 0;
  v_income numeric := 0;
  v_expense numeric := 0;
  v_asset_cost numeric := 0;
  v_asset_value numeric := 0;
  v_debt numeric := 0;
  v_business_value numeric := 0;
  v_share_units_total numeric := 0;
  v_share_price numeric := 0;
  v_ownership numeric := 0;
  v_profit numeric := 0;
  v_member_profit numeric := 0;
  v_current_value numeric := 0;
  v_share_system boolean := false;
  v_member_json jsonb;
begin
  if v_uid is null then
    raise exception 'Please login first.';
  end if;

  select * into v_member
  from public.members
  where auth_user_id = v_uid and active = true;

  if not found then
    raise exception 'No active member account is linked to this login.';
  end if;

  select a.data into v_state
  from public.app_state a
  where jsonb_typeof(a.data->'members') = 'array'
    and exists (
      select 1
      from jsonb_array_elements(a.data->'members') x
      where x->>'id' = v_member.id::text
    )
  order by a.updated_at desc
  limit 1;

  if v_state is null then
    raise exception 'Member financial data is not available in the Admin cloud backup yet.';
  end if;

  select x into v_member_json
  from jsonb_array_elements(v_state->'members') x
  where x->>'id' = v_member.id::text
  limit 1;

  if v_member_json is null then
    raise exception 'Member financial record was not found.';
  end if;

  v_members := coalesce(v_state->'members', '[]'::jsonb);
  v_entries := coalesce(v_state->'entries', '[]'::jsonb);
  v_assets := coalesce(v_state->'assets', '[]'::jsonb);
  v_liabilities := coalesce(v_state->'liabilities', '[]'::jsonb);
  v_share_system := coalesce((v_state->'shareSystem'->>'enabled')::boolean, false);

  select coalesce(sum(coalesce((m->>'invested')::numeric,0)),0)
    into v_capital
  from jsonb_array_elements(v_members) m;

  select
    coalesce(sum(case when e->>'type'='income' then coalesce((e->>'amount')::numeric,0) else 0 end),0),
    coalesce(sum(case when e->>'type'='expense' then coalesce((e->>'amount')::numeric,0) else 0 end),0)
    into v_income, v_expense
  from jsonb_array_elements(v_entries) e;

  select
    coalesce(sum(coalesce((a->>'cost')::numeric,0)),0),
    coalesce(sum(coalesce((a->>'value')::numeric,0)),0)
    into v_asset_cost, v_asset_value
  from jsonb_array_elements(v_assets) a;

  select coalesce(sum(coalesce((l->>'amount')::numeric,0)),0)
    into v_debt
  from jsonb_array_elements(v_liabilities) l;

  v_business_value := v_capital + v_income - v_expense - v_asset_cost + v_asset_value - v_debt;
  v_profit := v_income - v_expense;

  if v_share_system then
    select coalesce(sum(coalesce((m->>'shareUnits')::numeric,0)),0)
      into v_share_units_total
    from jsonb_array_elements(v_members) m;
    if v_share_units_total > 0 then
      v_share_price := greatest(0,v_business_value) / v_share_units_total;
    end if;
    v_ownership := case when v_share_units_total > 0
      then coalesce((v_member_json->>'shareUnits')::numeric,0) / v_share_units_total * 100 else 0 end;
    v_current_value := coalesce((v_member_json->>'shareUnits')::numeric,0) * v_share_price;
    v_member_profit := v_current_value - coalesce((v_member_json->>'invested')::numeric,0);
  else
    v_ownership := case when v_capital > 0
      then coalesce((v_member_json->>'invested')::numeric,0) / v_capital * 100 else 0 end;
    v_member_profit := case when v_capital > 0
      then coalesce((v_member_json->>'invested')::numeric,0) / v_capital * v_profit else 0 end;
    v_current_value := coalesce((v_member_json->>'invested')::numeric,0) + v_member_profit;
  end if;

  return jsonb_build_object(
    'member_id', v_member.id,
    'member_code', v_member.member_code,
    'name', v_member.full_name,
    'photo_url', coalesce(nullif(v_member.photo_url,''), nullif(v_member_json->>'photo',''), nullif(v_member_json->>'photo_url','')),
    'mobile', v_member.mobile,
    'address', v_member.address,
    'invested', coalesce((v_member_json->>'invested')::numeric,0),
    'share_units', coalesce((v_member_json->>'shareUnits')::numeric,0),
    'ownership_percent', round(v_ownership,2),
    'profit_loss', round(v_member_profit,2),
    'current_value', round(v_current_value,2),
    'capital_history', coalesce(v_member_json->'capitalHistory','[]'::jsonb),
    'share_system_enabled', v_share_system,
    'business_totals', jsonb_build_object(
      'total_capital', v_capital,
      'income', v_income,
      'expense', v_expense,
      'business_value', v_business_value
    )
  );
end;
$$;

revoke all on function public.get_my_member_statement() from public;
grant execute on function public.get_my_member_statement() to authenticated;
