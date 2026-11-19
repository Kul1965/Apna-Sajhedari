-- Member-to-Admin message thread RPC
-- This function inserts a private message tied only to the logged-in member's own record.
CREATE OR REPLACE FUNCTION public.send_my_member_message(
  p_title text DEFAULT 'Member ka message',
  p_body text DEFAULT ''
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
  v_message_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Member login zaroori hai.';
  END IF;

  IF length(trim(coalesce(p_body, ''))) = 0 THEN
    RAISE EXCEPTION 'Message khaali nahi ho sakta.';
  END IF;

  SELECT id
    INTO v_member_id
    FROM public.members
   WHERE auth_user_id = auth.uid()
     AND active IS DISTINCT FROM false
   LIMIT 1;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Is login se juda active member record nahi mila.';
  END IF;

  INSERT INTO public.member_messages
    (title, body, message_type, target_member_id, created_by, active)
  VALUES
    (coalesce(nullif(trim(p_title), ''), 'Member ka message'),
     trim(p_body),
     'personal',
     v_member_id,
     auth.uid(),
     true)
  RETURNING id INTO v_message_id;

  RETURN v_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.send_my_member_message(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_my_member_message(text, text) TO authenticated;
