-- Apna Sajhedari messaging v3: secure inbox and replies for both sides.
-- Does not delete or modify existing messages or financial/member data.
CREATE OR REPLACE FUNCTION public.admin_get_member_messages_v2()
RETURNS SETOF public.member_messages LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id=auth.uid() AND role='admin') THEN RAISE EXCEPTION 'Sirf Admin messages dekh sakta hai.'; END IF;
 RETURN QUERY SELECT m.* FROM public.member_messages m ORDER BY m.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_get_member_replies_v2()
RETURNS SETOF public.member_message_replies LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id=auth.uid() AND role='admin') THEN RAISE EXCEPTION 'Sirf Admin replies dekh sakta hai.'; END IF;
 RETURN QUERY SELECT r.* FROM public.member_message_replies r ORDER BY r.created_at ASC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_send_member_reply_v2(p_message_id uuid,p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id=auth.uid() AND role='admin') THEN RAISE EXCEPTION 'Sirf Admin reply bhej sakta hai.'; END IF;
 IF length(trim(coalesce(p_body,'')))=0 THEN RAISE EXCEPTION 'Reply khaali nahi ho sakta.'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.member_messages WHERE id=p_message_id) THEN RAISE EXCEPTION 'Message nahi mila.'; END IF;
 INSERT INTO public.member_message_replies(message_id,sender_id,sender_role,body) VALUES(p_message_id,auth.uid(),'admin',trim(p_body)) RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.member_get_my_message_replies_v2()
RETURNS SETOF public.member_message_replies LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_member_id uuid;
BEGIN
 SELECT id INTO v_member_id FROM public.members WHERE auth_user_id=auth.uid() AND active IS DISTINCT FROM false LIMIT 1;
 IF v_member_id IS NULL THEN RAISE EXCEPTION 'Member account nahi mila.'; END IF;
 RETURN QUERY SELECT r.* FROM public.member_message_replies r JOIN public.member_messages m ON m.id=r.message_id WHERE m.target_member_id=v_member_id ORDER BY r.created_at ASC;
END; $$;

CREATE OR REPLACE FUNCTION public.member_send_message_reply_v2(p_message_id uuid,p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_member_id uuid; v_id uuid;
BEGIN
 SELECT id INTO v_member_id FROM public.members WHERE auth_user_id=auth.uid() AND active IS DISTINCT FROM false LIMIT 1;
 IF v_member_id IS NULL THEN RAISE EXCEPTION 'Member account nahi mila.'; END IF;
 IF length(trim(coalesce(p_body,'')))=0 THEN RAISE EXCEPTION 'Reply khaali nahi ho sakta.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.member_messages WHERE id=p_message_id AND target_member_id=v_member_id AND active IS DISTINCT FROM false) THEN RAISE EXCEPTION 'Yeh message aapke account ka nahi hai.'; END IF;
 INSERT INTO public.member_message_replies(message_id,sender_id,sender_role,body) VALUES(p_message_id,auth.uid(),'member',trim(p_body)) RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

REVOKE ALL ON FUNCTION public.admin_get_member_messages_v2() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_get_member_replies_v2() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_send_member_reply_v2(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.member_get_my_message_replies_v2() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.member_send_message_reply_v2(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_member_messages_v2() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_member_replies_v2() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_member_reply_v2(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.member_get_my_message_replies_v2() TO authenticated;
GRANT EXECUTE ON FUNCTION public.member_send_message_reply_v2(uuid,text) TO authenticated;
NOTIFY pgrst,'reload schema';
