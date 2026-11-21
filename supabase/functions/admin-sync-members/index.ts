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
    console.log("admin-sync-members request", JSON.stringify({ action: body?.action || null, member_id: body?.member_id || null, has_members_array: Array.isArray(body?.members), body_keys: body && typeof body === "object" ? Object.keys(body) : [] }));
    // Accept explicit action or member_id-only delete request.
    if (body?.action === "delete_member_conversation" || (body?.member_id && !Array.isArray(body?.members))) {
      console.log("member conversation delete started", String(body.member_id || ""));
      const memberId = String(body.member_id || "").trim();
      if (!memberId) { console.error("DELETE_VALIDATION missing member_id", JSON.stringify(body)); return reply({ error: "Member ID nahi mila. Request keys: " + Object.keys(body || {}).join(",") }, 400); }
      const { data: member, error: memberError } = await admin.from("members").select("id, auth_user_id").eq("id", memberId).maybeSingle();
      if (memberError) { console.error("DELETE_MEMBER_LOOKUP", memberError); return reply({ error: "Member check nahi hua: " + memberError.message }, 500); }
      if (!member) { console.error("DELETE_MEMBER_NOT_FOUND", memberId); return reply({ error: "Member nahi mila: " + memberId }, 404); }
      const { data: allMessages, error: messagesError } = await userClient.rpc("admin_get_member_messages_v2");
      if (messagesError) { console.error("DELETE_MESSAGES_RPC", messagesError); return reply({ error: "Messages load nahi hue: " + messagesError.message }, 500); }
      const memberMessages = (allMessages || []).filter((row: any) => String(row.target_member_id) === memberId || (!!member.auth_user_id && String(row.created_by) === String(member.auth_user_id)));
      const messageIds = [...new Set(memberMessages.map((row: any) => String(row.id)))];
      const { data: allReplies, error: repliesError } = await userClient.rpc("admin_get_member_replies_v2");
      if (repliesError) { console.error("DELETE_REPLIES_RPC", repliesError); return reply({ error: "Replies load nahi hue: " + repliesError.message }, 500); }
      const messageIdSet = new Set(messageIds);
      const replies = (allReplies || []).filter((row: any) => messageIdSet.has(String(row.message_id)));
      const paths = [...new Set([...memberMessages.map((row: any) => row.attachment_path), ...replies.map((row: any) => row.attachment_path)].filter((p: any) => typeof p === "string" && p.length > 0))];
      for (let i = 0; i < paths.length; i += 100) {
        const { error } = await admin.storage.from("member-chat-photos").remove(paths.slice(i, i + 100));
        if (error) { console.error("DELETE_STORAGE", error); return reply({ error: "Chat photo delete nahi hui: " + error.message }, 500); }
      }
      const { data: deletedCount, error: deleteError } = await userClient.rpc("admin_delete_member_conversation_v1", { p_member_id: memberId });
      if (deleteError) { console.error("DELETE_CONVERSATION_RPC", deleteError); return reply({ error: "Conversation database se delete nahi hui: " + deleteError.message }, 500); }
      return reply({ success: true, deleted_messages: Number(deletedCount) || messageIds.length, deleted_replies: replies.length, deleted_photos: paths.length });
    }
    // FARM / TEMPO STAFF CONVERSATION DELETE
    if (body?.action === "delete_worker_conversation") {
      const workerAccountId = String(body.worker_account_id || "").trim();
      if (!workerAccountId) return reply({ error: "Staff account ID nahi mila." }, 400);

      const { data: allAccounts, error: accountsError } = await userClient.rpc("admin_get_worker_messages_v1");
      if (accountsError) return reply({ error: "Staff messages load nahi hue: " + accountsError.message }, 500);
      const account = (allAccounts || []).find((row: any) => String(row.account_id) === workerAccountId);
      if (!account) return reply({ error: "Staff conversation nahi mili." }, 404);

      const messages = Array.isArray(account.messages) ? account.messages : [];
      const paths = [...new Set(messages.map((row: any) => row.attachment_path).filter((path: any) => typeof path === "string" && path.length > 0))];
      for (let i = 0; i < paths.length; i += 100) {
        const { error } = await admin.storage.from("member-chat-photos").remove(paths.slice(i, i + 100));
        if (error) {
          console.error("DELETE STAFF CHAT PHOTOS", error);
          return reply({ error: "Staff chat photo delete nahi hui: " + error.message }, 500);
        }
      }

      const { data: deletedCount, error: deleteError } = await userClient.rpc("admin_delete_worker_conversation_v1", { p_worker_account_id: workerAccountId });
      if (deleteError) {
        console.error("DELETE STAFF CONVERSATION RPC", deleteError);
        return reply({ error: "Staff conversation database se delete nahi hui: " + deleteError.message }, 500);
      }
      return reply({ success: true, deleted_messages: Number(deletedCount) || messages.length, deleted_photos: paths.length });
    }

    if (!Array.isArray(body.members)) { console.error("SYNC_VALIDATION missing members array", JSON.stringify({ keys: Object.keys(body || {}), action: body?.action || null, member_id: body?.member_id || null })); return reply({ error: "Members list nahi mili. Delete action nahi mila; received keys: " + Object.keys(body || {}).join(",") }, 400); }
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
