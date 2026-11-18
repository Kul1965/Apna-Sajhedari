-- Apna Sajhedari: member OTP access + Admin approval
-- Run once in Supabase SQL Editor AFTER database-setup.sql.
-- This migration does not delete or overwrite existing member/app data.
-- Member phone numbers should be stored with country code (for example +91...).

create table if not exists public.member_access_requests (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  verified_phone text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  unique (member_id, auth_user_id)
);

alter table public.member_access_requests enable row level security;

drop policy if exists "admin reads member access requests" on public.member_access_requests;
create policy "admin reads member access requests"
on public.member_access_requests for select to authenticated
using (public.is_admin());

grant select on public.member_access_requests to authenticated;

-- A member calls this only AFTER Supabase Phone OTP verification.
-- The verified phone comes from the signed-in Auth JWT, never from a client parameter.
create or replace function public.request_my_member_access()
returns table(request_id uuid, request_status text, matched_member_name text)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_phone text := coalesce(auth.jwt() ->> 'phone', '');
  v_digits text;
  v_member_id uuid;
  v_member_name text;
  v_count integer;
  v_request_id uuid;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Please verify your mobile number first.';
  end if;
  v_digits := regexp_replace(v_phone, '[^0-9]', '', 'g');
  if length(v_digits) < 10 then
    raise exception 'Verified mobile number is missing. Please sign in using Phone OTP.';
  end if;

  select count(*)
    into v_count
  from public.members m
  where m.active = true
    and regexp_replace(coalesce(m.mobile,''), '[^0-9]', '', 'g') <> ''
    and (
      regexp_replace(m.mobile, '[^0-9]', '', 'g') = v_digits
      or (
        length(regexp_replace(m.mobile, '[^0-9]', '', 'g')) >= 10
        and right(regexp_replace(m.mobile, '[^0-9]', '', 'g'), 10) = right(v_digits, 10)
      )
    );

  if v_count <> 1 then
    raise exception 'Mobile number did not match exactly one active member. Please ask Admin to check the saved number.';
  end if;

  select m.id, m.full_name into v_member_id, v_member_name
  from public.members m
  where m.active = true
    and (
      regexp_replace(m.mobile, '[^0-9]', '', 'g') = v_digits
      or (
        length(regexp_replace(m.mobile, '[^0-9]', '', 'g')) >= 10
        and right(regexp_replace(m.mobile, '[^0-9]', '', 'g'), 10) = right(v_digits, 10)
      )
    )
  limit 1;

  if exists (
    select 1 from public.members m
    where m.id = v_member_id and m.auth_user_id is not null and m.auth_user_id <> v_uid
  ) then
    raise exception 'This member account is already linked. Please contact Admin.';
  end if;

  insert into public.member_access_requests(member_id, auth_user_id, verified_phone, status)
  values (v_member_id, v_uid, v_phone, 'pending')
  on conflict (auth_user_id) do update
    set member_id = excluded.member_id,
        verified_phone = excluded.verified_phone,
        status = case
          when public.member_access_requests.status = 'approved' then 'approved'
          else 'pending'
        end,
        requested_at = now()
  returning id, status into v_request_id, v_status;

  return query select v_request_id, v_status, v_member_name;
end;
$$;

-- Admin approves a verified request and links exactly that Auth user to exactly that member.
create or replace function public.admin_review_member_access(
  p_request_id uuid,
  p_approve boolean
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_req public.member_access_requests%rowtype;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Admin permission required.';
  end if;

  select * into v_req
  from public.member_access_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Approval request not found.';
  end if;

  if p_approve then
    if exists (
      select 1 from public.members
      where id = v_req.member_id
        and auth_user_id is not null
        and auth_user_id <> v_req.auth_user_id
    ) then
      raise exception 'This member is already linked to another login.';
    end if;

    update public.members
      set auth_user_id = v_req.auth_user_id
      where id = v_req.member_id and active = true;

    if not found then
      raise exception 'Member is inactive or no longer exists.';
    end if;

    insert into public.user_profiles(user_id, role, display_name)
    select v_req.auth_user_id, 'member', m.full_name
    from public.members m where m.id = v_req.member_id
    on conflict (user_id) do update
      set role = 'member', display_name = excluded.display_name;

    update public.member_access_requests
      set status = 'approved', reviewed_at = now(), reviewed_by = auth.uid()
      where id = p_request_id;

    return 'approved';
  else
    update public.member_access_requests
      set status = 'rejected', reviewed_at = now(), reviewed_by = auth.uid()
      where id = p_request_id;
    return 'rejected';
  end if;
end;
$$;

revoke all on function public.request_my_member_access() from public;
revoke all on function public.admin_review_member_access(uuid, boolean) from public;
grant execute on function public.request_my_member_access() to authenticated;
grant execute on function public.admin_review_member_access(uuid, boolean) to authenticated;
