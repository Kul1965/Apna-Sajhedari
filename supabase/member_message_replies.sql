-- Apna Sajhedari — Member message replies
-- IMPORTANT: The live database already has this table and its RLS policies.
-- Existing columns: id, message_id, sender_id, sender_role, body, created_at.
-- Existing policies: sajhedari_message_replies_insert and sajhedari_message_replies_select.
-- No schema change is required for the reply feature. The app now uses sender_id
-- and sender_role to match the existing table.
--
-- Read-only verification query (safe to run; changes nothing):
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'member_message_replies'
order by ordinal_position;
