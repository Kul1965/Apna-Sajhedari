-- Apna Sajhedari: fix sender identity in the member chat inbox.
-- Safe function replacement only; does not change or delete any message or member data.
CREATE OR REPLACE FUNCTION public.get_my_member_messages()
RETURNS TABLE (
  id uuid,
  title text,
  body text,
  message_type text,
  created_at timestamptz,
  is_read boolean,
  created_by uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id
  FROM public.members m
  WHERE m.auth_user_id = auth.uid() AND m.active = true
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Active member account not found.';
  END IF;

  INSERT INTO public.member_message_reads(message_id, member_id)
  SELECT mm.id, v_member_id
  FROM public.member_messages mm
  WHERE mm.active = true
    AND (mm.target_member_id IS NULL OR mm.target_member_id = v_member_id)
  ON CONFLICT (message_id, member_id) DO NOTHING;

  RETURN QUERY
  SELECT mm.id, mm.title, mm.body, mm.message_type, mm.created_at, true, mm.created_by
  FROM public.member_messages mm
  WHERE mm.active = true
    AND (mm.target_member_id IS NULL OR mm.target_member_id = v_member_id)
  ORDER BY mm.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_member_messages() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_member_messages() TO authenticated;
NOTIFY pgrst, 'reload schema';
