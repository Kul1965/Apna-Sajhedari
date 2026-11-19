import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Admin login required." }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) {
      return json({ error: "Server configuration incomplete." }, 500);
    }

    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: callerData, error: callerError } = await callerClient.auth.getUser();
    if (callerError || !callerData.user) return json({ error: "Admin session invalid hai." }, 401);

    const adminClient = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: profile, error: profileError } = await adminClient
      .from("user_profiles").select("role")
      .eq("user_id", callerData.user.id).maybeSingle();
    if (profileError) throw profileError;
    if (profile?.role !== "admin") return json({ error: "Sirf Admin member account bana sakta hai." }, 403);

    const body = await req.json();
    const memberId = String(body.member_id || "").trim();
    const password = String(body.password || "");
    if (!memberId) return json({ error: "Member select nahi hua." }, 400);
    if (password.length < 8) return json({ error: "Password kam se kam 8 characters ka rakhein." }, 400);

    const { data: member, error: memberError } = await adminClient
      .from("members").select("id,full_name,mobile,active,auth_user_id")
      .eq("id", memberId).maybeSingle();
    if (memberError) throw memberError;
    if (!member || member.active === false) return json({ error: "Active member record nahi mila." }, 404);

    // Accept common display formats such as +61 452 430 783 or +91-XXXXXXXXXX.
    // Store/use the normalized E.164-style value for Supabase Auth.
    const rawPhone = String(member.mobile || "").trim();
    const phone = rawPhone.replace(/[^\d+]/g, "");
    if (!/^\+[1-9][0-9]{7,14}$/.test(phone)) {
      return json({ error: "Member ka mobile number country code ke saath (+91...) save karein." }, 400);
    }

    let userId = member.auth_user_id as string | null;
    let existingUser = null;
    if (userId) {
      const { data, error } = await adminClient.auth.admin.getUserById(userId);
      if (error || !data.user) return json({ error: "Linked Auth account nahi mila; Admin se support lein." }, 409);
      existingUser = data.user;
    } else {
      const { data: usersData, error: usersError } = await adminClient.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (usersError) throw usersError;
      existingUser = usersData.users.find((u) => u.phone === phone) || null;
      if (existingUser) {
        const { data: linked, error: linkedError } = await adminClient
          .from("members").select("id").eq("auth_user_id", existingUser.id).maybeSingle();
        if (linkedError) throw linkedError;
        if (linked && linked.id !== memberId) {
          return json({ error: "Yeh mobile number kisi doosre member account se juda hai." }, 409);
        }
        userId = existingUser.id;
      }
    }

    if (userId) {
      const { error } = await adminClient.auth.admin.updateUserById(userId, {
        password, phone, phone_confirm: true,
        user_metadata: { role: "member", member_name: member.full_name },
      });
      if (error) throw error;
    } else {
      const { data, error } = await adminClient.auth.admin.createUser({
        phone, password, phone_confirm: true,
        user_metadata: { role: "member", member_name: member.full_name },
      });
      if (error) throw error;
      userId = data.user.id;
    }

    const { error: linkError } = await adminClient.from("members")
      .update({ auth_user_id: userId }).eq("id", memberId);
    if (linkError) throw linkError;
    const { error: profileUpsertError } = await adminClient.from("user_profiles").upsert({
      user_id: userId, role: "member", display_name: member.full_name,
    }, { onConflict: "user_id" });
    if (profileUpsertError) throw profileUpsertError;

    return json({ success: true, member_name: member.full_name, phone, updated: !!existingUser });
  } catch (error) {
    console.error("admin-create-member:", error);
    return json({ error: error instanceof Error ? error.message : "Account create nahi hua." }, 400);
  }
});
