-- Apna Sajhedari: shared Admin profile for private chat
-- Run once in Supabase SQL Editor. Safe additive migration; existing rows/data remain.
alter table public.user_profiles
  add column if not exists avatar_url text;

create or replace function public.get_admin_public_profile_v1()
returns table(display_name text, avatar_url text)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(p.display_name,''),'Admin'), p.avatar_url
  from public.user_profiles p
  where p.role = 'admin'
  order by p.created_at
  limit 1;
$$;

revoke all on function public.get_admin_public_profile_v1() from public;
grant execute on function public.get_admin_public_profile_v1() to authenticated;
