-- Apna Sajhedari: private photo messaging setup.
-- Safe to run again. Does not change member, ledger, or financial records.

ALTER TABLE public.member_messages
  ADD COLUMN IF NOT EXISTS attachment_path text;

ALTER TABLE public.member_message_replies
  ADD COLUMN IF NOT EXISTS attachment_path text;

INSERT INTO storage.buckets
  (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('member-chat-photos', 'member-chat-photos', false, 2097152,
   ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 2097152,
  allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp'];

DROP POLICY IF EXISTS "chat photos upload" ON storage.objects;
CREATE POLICY "chat photos upload"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'member-chat-photos'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id::text = (storage.foldername(name))[1]
        AND m.auth_user_id = auth.uid()
        AND m.active IS DISTINCT FROM false
    )
  )
);

DROP POLICY IF EXISTS "chat photos read" ON storage.objects;
CREATE POLICY "chat photos read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'member-chat-photos'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id::text = (storage.foldername(name))[1]
        AND m.auth_user_id = auth.uid()
        AND m.active IS DISTINCT FROM false
    )
  )
);

DROP POLICY IF EXISTS "chat photos delete" ON storage.objects;
CREATE POLICY "chat photos delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'member-chat-photos'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.id::text = (storage.foldername(name))[1]
        AND m.auth_user_id = auth.uid()
        AND m.active IS DISTINCT FROM false
    )
  )
);

CREATE OR REPLACE FUNCTION public.member_send_message_photo_v1(
  p_body text,
  p_attachment_path text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
  v_message_id uuid;
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Member login zaroori hai.';
  END IF;

  SELECT id INTO v_member_id
  FROM public.members
  WHERE auth_user_id = v_user_id AND active IS DISTINCT FROM false
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Active member account nahi mila.';
  END IF;

  IF p_attachment_path IS NULL
     OR p_attachment_path !~ ('^' || v_member_id::text || '/' || v_user_id::text || '/[^/]+$') THEN
    RAISE EXCEPTION 'Photo path member account se match nahi karta.';
  END IF;

  INSERT INTO public.member_messages
    (title, body, message_type, target_member_id, created_by, active, attachment_path)
  VALUES
    ('Member ka photo', coalesce(nullif(trim(p_body), ''), '📷 Photo'),
     'personal', v_member_id, v_user_id, true, p_attachment_path)
  RETURNING id INTO v_message_id;

  RETURN v_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.member_send_message_reply_photo_v1(
  p_message_id uuid,
  p_body text,
  p_attachment_path text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
  v_reply_id uuid;
  v_user_id uuid := auth.uid();
BEGIN
  SELECT id INTO v_member_id
  FROM public.members
  WHERE auth_user_id = v_user_id AND active IS DISTINCT FROM false
  LIMIT 1;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Member account nahi mila.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.member_messages
    WHERE id = p_message_id
      AND target_member_id = v_member_id
      AND active IS DISTINCT FROM false
  ) THEN
    RAISE EXCEPTION 'Yeh conversation aapke account ki nahi hai.';
  END IF;

  IF p_attachment_path IS NULL
     OR p_attachment_path !~ ('^' || v_member_id::text || '/' || v_user_id::text || '/[^/]+$') THEN
    RAISE EXCEPTION 'Photo path member account se match nahi karta.';
  END IF;

  INSERT INTO public.member_message_replies
    (message_id, sender_id, sender_role, body, attachment_path)
  VALUES
    (p_message_id, v_user_id, 'member',
     coalesce(nullif(trim(p_body), ''), '📷 Photo'), p_attachment_path)
  RETURNING id INTO v_reply_id;

  RETURN v_reply_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_send_member_message_photo_v1(
  p_member_id uuid,
  p_body text,
  p_attachment_path text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_message_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Sirf Admin photo message bhej sakta hai.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.members
    WHERE id = p_member_id AND active IS DISTINCT FROM false
  ) THEN
    RAISE EXCEPTION 'Active member nahi mila.';
  END IF;

  IF p_attachment_path IS NULL
     OR p_attachment_path !~ ('^' || p_member_id::text || '/' || v_user_id::text || '/[^/]+$') THEN
    RAISE EXCEPTION 'Photo path member account se match nahi karta.';
  END IF;

  INSERT INTO public.member_messages
    (title, body, message_type, target_member_id, created_by, active, attachment_path)
  VALUES
    ('Admin ka photo', coalesce(nullif(trim(p_body), ''), '📷 Photo'),
     'personal', p_member_id, v_user_id, true, p_attachment_path)
  RETURNING id INTO v_message_id;

  RETURN v_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_send_member_reply_photo_v1(
  p_message_id uuid,
  p_body text,
  p_attachment_path text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
  v_reply_id uuid;
  v_user_id uuid := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Sirf Admin photo reply bhej sakta hai.';
  END IF;

  SELECT target_member_id INTO v_member_id
  FROM public.member_messages
  WHERE id = p_message_id;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Member conversation nahi mili.';
  END IF;

  IF p_attachment_path IS NULL
     OR p_attachment_path !~ ('^' || v_member_id::text || '/' || v_user_id::text || '/[^/]+$') THEN
    RAISE EXCEPTION 'Photo path member conversation se match nahi karta.';
  END IF;

  INSERT INTO public.member_message_replies
    (message_id, sender_id, sender_role, body, attachment_path)
  VALUES
    (p_message_id, v_user_id, 'admin',
     coalesce(nullif(trim(p_body), ''), '📷 Photo'), p_attachment_path)
  RETURNING id INTO v_reply_id;

  RETURN v_reply_id;
END;
$$;

REVOKE ALL ON FUNCTION public.member_send_message_photo_v1(text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.member_send_message_reply_photo_v1(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_send_member_message_photo_v1(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_send_member_reply_photo_v1(uuid,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.member_send_message_photo_v1(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.member_send_message_reply_photo_v1(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_member_message_photo_v1(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_send_member_reply_photo_v1(uuid,text,text) TO authenticated;

-- Keep the existing Delete Conversation action, and also remove that
-- conversation's stored photo files. Other member/data records are untouched.
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

  DELETE FROM storage.objects
  WHERE bucket_id = 'member-chat-photos'
    AND name IN (
      SELECT r.attachment_path
      FROM public.member_message_replies r
      JOIN public.member_messages m ON m.id = r.message_id
      WHERE (m.target_member_id = p_member_id
         OR (v_auth_user_id IS NOT NULL AND m.created_by = v_auth_user_id))
        AND r.attachment_path IS NOT NULL
      UNION
      SELECT m.attachment_path
      FROM public.member_messages m
      WHERE (m.target_member_id = p_member_id
         OR (v_auth_user_id IS NOT NULL AND m.created_by = v_auth_user_id))
        AND m.attachment_path IS NOT NULL
    );

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
