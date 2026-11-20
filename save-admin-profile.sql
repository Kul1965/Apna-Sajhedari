-- Apna Sajhedari: save Admin name + photo through one secure RPC.
-- Additive change only; no existing member/business data is deleted.
create or replace function public.save_my_admin_profile_v1(
  p_display_name text,
  p_avatar_url text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Sirf Admin apna profile badal sakta hai.';
  end if;

  update public.user_profiles
  set display_name = nullif(trim(p_display_name), ''),
      avatar_url = p_avatar_url
  where user_id = auth.uid()
    and role = 'admin';

  if not found then
    raise exception 'Admin profile record nahi mila.';
  end if;
end;
$$;

revoke all on function public.save_my_admin_profile_v1(text,text) from public;
grant execute on function public.save_my_admin_profile_v1(text,text) to authenticated;
