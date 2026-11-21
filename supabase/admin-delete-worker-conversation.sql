-- Admin-only deletion of one selected Farm / Tempo staff conversation.
-- This removes messages only. Staff account, duty, salary and payment records remain untouched.
CREATE OR REPLACE FUNCTION public.admin_delete_worker_conversation_v1(p_worker_account_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_deleted integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Sirf Admin staff conversation delete kar sakta hai.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.worker_accounts
    WHERE id = p_worker_account_id
  ) THEN
    RAISE EXCEPTION 'Staff account nahi mila.';
  END IF;

  DELETE FROM public.worker_messages
  WHERE worker_account_id = p_worker_account_id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_worker_conversation_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_worker_conversation_v1(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
