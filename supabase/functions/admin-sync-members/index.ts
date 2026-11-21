import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-api-version, x-supabase-client-platform, x-supabase-client-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Vary": "Origin",
};
function reply(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Sirf POST request allowed hai." }, 405);
  try {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
    if (!token) return reply({ error: "Admin login nahi mila." }, 401);
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return reply({ error: "Supabase Function secrets adhure hain." }, 500);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const userClient = createClient(url, serviceKey, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return reply({ error: "Admin session expire ho gaya." }, 401);
    const { data: profile, error: profileError } = await admin.from("user_profiles").select("role").eq("user_id", authData.user.id).maybeSingle();
    if (profileError || profile?.role !== "admin") return reply({ error: "Sirf Admin member list Cloud mein bhej sakta hai." }, 403);

    const body = await req.json();
    // Admin-only conversation deletion; use Storage API, not SQL on storage.objects.
    if (body.action === "delete_member_conversation") {
      const memberId = String(body.member_id || "").trim();
      if (!memberId) return reply({ error: "Member ID nahi mila." }, 400);
      const { data: member, error: memberError } = await admin.from("members").select("id, auth_user_id").eq("id", memberId).maybeSingle();
      if (memberError) return reply({ error: "Member check nahi hua: " + memberError.message }, 500);
      if (!member) return reply({ error: "Member nahi mila." }, 404);
      const { data: allMessages, error: messagesError } = await userClient.rpc("admin_get_member_messages_v2");
      if (messagesError) return reply({ error: "Messages load nahi hue: " + messagesError.message }, 500);
      const memberMessages = (allMessages || []).filter((row: any) => String(row.target_member_id) === memberId || (!!member.auth_user_id && String(row.created_by) === String(member.auth_user_id)));
      const messageIds = [...new Set(memberMessages.map((row: any) => String(row.id)))];
      const { data: allReplies, error: repliesError } = await userClient.rpc("admin_get_member_replies_v2");
      if (repliesError) return reply({ error: "Replies load nahi hue: " + repliesError.message }, 500);
      const messageIdSet = new Set(messageIds);
      const replies = (allReplies || []).filter((row: any) => messageIdSet.has(String(row.message_id)));
      const paths = [...new Set([...memberMessages.map((row: any) => row.attachment_path), ...replies.map((row: any) => row.attachment_path)].filter((p: any) => typeof p === "string" && p.length > 0))];
      for (let i = 0; i < paths.length; i += 100) {
        const { error } = await admin.storage.from("member-chat-photos").remove(paths.slice(i, i + 100));
        if (error) return reply({ error: "Chat photo delete nahi hui: " + error.message }, 500);
      }
      const { data: deletedCount, error: deleteError } = await userClient.rpc("admin_delete_member_conversation_v1", { p_member_id: memberId });
      if (deleteError) return reply({ error: "Conversation database se delete nahi hui: " + deleteError.message }, 500);
      return reply({ success: true, deleted_messages: Number(deletedCount) || messageIds.length, deleted_replies: replies.length, deleted_photos: paths.length });
    }
    if (!Array.isArray(body.members)) return reply({ error: "Members list nahi mili." }, 400);
    if (body.members.length > 500) return reply({ error: "Members list bahut badi hai." }, 400);

    const rows = body.members.filter((m: any) => m && m.id).map((m: any) => ({
      id: m.id,
      member_code: "ASJ-" + String(m.id).replace(/-/g, "").slice(0, 8).toUpperCase(),
      full_name: String(m.name || "Member").trim(),
      mobile: String(m.phone || "").trim() || null,
      address: String(m.address || "").trim() || null,
      note: String(m.note || "").trim() || null,
      active: true,
    }));
    if (rows.length) {
      const { error } = await admin.from("members").upsert(rows, { onConflict: "id" });
      if (error) return reply({ error: "Members Cloud mein save nahi hue: " + error.message }, 500);
    }
    return reply({ success: true, synced_count: rows.length });
  } catch (error) {
    return reply({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
