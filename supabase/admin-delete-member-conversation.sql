-- Safely delete only one member's message conversation and its replies.
CREATE OR REPLACE FUNCTION public.admin_delete_member_conversation_v1(p_member_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth_user_id uuid;
  v_deleted integer := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.user_profiles
    WHERE user_id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Sirf Admin conversation delete kar sakta hai.';
  END IF;

  SELECT auth_user_id INTO v_auth_user_id
  FROM public.members
  WHERE id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member nahi mila.';
  END IF;

  DELETE FROM public.member_message_replies
  WHERE message_id IN (
    SELECT id FROM public.member_messages
    WHERE target_member_id = p_member_id
       OR (v_auth_user_id IS NOT NULL AND created_by = v_auth_user_id)
  );

  DELETE FROM public.member_messages
  WHERE target_member_id = p_member_id
     OR (v_auth_user_id IS NOT NULL AND created_by = v_auth_user_id);

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_member_conversation_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_member_conversation_v1(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
