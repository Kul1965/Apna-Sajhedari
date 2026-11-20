import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function reply(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Sirf POST request allowed hai." }, 405);
  try {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
    if (!token) return reply({ error: "Admin login nahi mila." }, 401);
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return reply({ error: "Supabase Function secrets adhure hain." }, 500);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return reply({ error: "Admin session expire ho gaya." }, 401);
    const { data: profile, error: profileError } = await admin.from("user_profiles").select("role").eq("user_id", authData.user.id).maybeSingle();
    if (profileError || profile?.role !== "admin") return reply({ error: "Sirf Admin member list Cloud mein bhej sakta hai." }, 403);

    const body = await req.json();
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
