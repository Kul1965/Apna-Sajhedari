-- Staff / Farm / Tempo private chat photo support.
-- Additive only: keeps all existing staff accounts, messages and financial records.
ALTER TABLE public.worker_messages
  ADD COLUMN IF NOT EXISTS attachment_path text;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('member-chat-photos','member-chat-photos',false,2097152,ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=2097152,allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp'];

DROP POLICY IF EXISTS "chat photos upload" ON storage.objects;
CREATE POLICY "chat photos upload" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
 bucket_id='member-chat-photos'
 AND (storage.foldername(name))[2]=auth.uid()::text
 AND (
  public.is_admin()
  OR EXISTS(SELECT 1 FROM public.members m WHERE m.id::text=(storage.foldername(name))[1] AND m.auth_user_id=auth.uid() AND m.active IS DISTINCT FROM false)
  OR EXISTS(SELECT 1 FROM public.worker_accounts w WHERE w.id::text=(storage.foldername(name))[1] AND w.auth_user_id=auth.uid() AND w.active=true)
 )
);

DROP POLICY IF EXISTS "chat photos read" ON storage.objects;
CREATE POLICY "chat photos read" ON storage.objects FOR SELECT TO authenticated
USING (
 bucket_id='member-chat-photos'
 AND (
  public.is_admin()
  OR EXISTS(SELECT 1 FROM public.members m WHERE m.id::text=(storage.foldername(name))[1] AND m.auth_user_id=auth.uid() AND m.active IS DISTINCT FROM false)
  OR EXISTS(SELECT 1 FROM public.worker_accounts w WHERE w.id::text=(storage.foldername(name))[1] AND w.auth_user_id=auth.uid() AND w.active=true)
 )
);

DROP POLICY IF EXISTS "chat photos delete" ON storage.objects;
CREATE POLICY "chat photos delete" ON storage.objects FOR DELETE TO authenticated
USING (
 bucket_id='member-chat-photos'
 AND (
  public.is_admin()
  OR EXISTS(SELECT 1 FROM public.members m WHERE m.id::text=(storage.foldername(name))[1] AND m.auth_user_id=auth.uid() AND m.active IS DISTINCT FROM false)
  OR EXISTS(SELECT 1 FROM public.worker_accounts w WHERE w.id::text=(storage.foldername(name))[1] AND w.auth_user_id=auth.uid() AND w.active=true)
 )
);

CREATE OR REPLACE FUNCTION public.worker_send_message_photo_v1(p_body text,p_attachment_path text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_uid uuid:=auth.uid();v_account uuid;v_id uuid;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Please login first.'; END IF;
 SELECT id INTO v_account FROM public.worker_accounts WHERE auth_user_id=v_uid AND active=true ORDER BY created_at LIMIT 1;
 IF v_account IS NULL THEN RAISE EXCEPTION 'Active staff account not found.'; END IF;
 IF p_attachment_path IS NULL OR p_attachment_path !~ ('^'||v_account::text||'/'||v_uid::text||'/[^/]+$') THEN
  RAISE EXCEPTION 'Photo path staff account se match nahi karta.';
 END IF;
 INSERT INTO public.worker_messages(worker_account_id,sender_user_id,sender_role,body,attachment_path)
 VALUES(v_account,v_uid,'worker',coalesce(nullif(trim(p_body),''),'📷 Photo'),p_attachment_path)
 RETURNING id INTO v_id;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.get_my_worker_messages_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_uid uuid:=auth.uid();v_result jsonb;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Please login first.'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'account_id',wa.id,'worker_type',wa.worker_type,'display_name',wa.display_name,
  'messages',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'id',wm.id,'sender_role',wm.sender_role,'body',wm.body,'attachment_path',wm.attachment_path,'created_at',wm.created_at
  ) ORDER BY wm.created_at) FROM public.worker_messages wm WHERE wm.worker_account_id=wa.id),'[]'::jsonb)
  )),'[]'::jsonb) INTO v_result
 FROM public.worker_accounts wa WHERE wa.auth_user_id=v_uid AND wa.active=true;
 RETURN v_result;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_get_worker_messages_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_uid uuid:=auth.uid();v_result jsonb;
BEGIN
 IF v_uid IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Only Admin can view staff conversations.'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'account_id',wa.id,'worker_type',wa.worker_type,'worker_id',wa.worker_id,'display_name',wa.display_name,
  'mobile',wa.mobile,'auth_user_id',wa.auth_user_id,
  'messages',coalesce((SELECT jsonb_agg(jsonb_build_object(
   'id',wm.id,'sender_user_id',wm.sender_user_id,'sender_role',wm.sender_role,'body',wm.body,
   'attachment_path',wm.attachment_path,'created_at',wm.created_at
  ) ORDER BY wm.created_at) FROM public.worker_messages wm WHERE wm.worker_account_id=wa.id),'[]'::jsonb)
 ) ORDER BY wa.display_name),'[]'::jsonb) INTO v_result
 FROM public.worker_accounts wa WHERE wa.active=true;
 RETURN v_result;
END; $$;

REVOKE ALL ON FUNCTION public.worker_send_message_photo_v1(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.worker_send_message_photo_v1(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_worker_messages_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_worker_messages_v1() TO authenticated;
NOTIFY pgrst,'reload schema';
