import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Sirf POST request allowed hai." }, 405);

  let stage = "request";
  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\\s+/i, "").trim();
    if (!token) return reply({ error: "Admin login nahi mila. App mein Admin se dobara login karein.", stage }, 401);

    stage = "server configuration";
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) {
      console.error("admin-create-member missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
      return reply({ error: "Supabase Function ki server setting adhuri hai. SUPABASE_URL aur SUPABASE_SERVICE_ROLE_KEY secret check karna hoga.", stage }, 500);
    }

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    stage = "admin session verification";
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) {
      console.error("admin session verification failed:", authError?.message);
      return reply({ error: "Admin login expire ho gaya. App mein Admin se dobara login karein.", stage }, 401);
    }

    stage = "admin permission check";
    const { data: profile, error: profileError } = await admin
      .from("user_profiles")
      .select("role")
      .eq("user_id", authData.user.id)
      .maybeSingle();
    if (profileError) {
      console.error("user_profiles lookup failed:", profileError.message);
      return reply({ error: "Admin ka role check nahi hua: " + profileError.message, stage }, 500);
    }
    if (profile?.role !== "admin") {
      return reply({ error: "Sirf Admin member ka Login bana sakta hai.", stage }, 403);
    }

    stage = "request data";
    let body: Record<string, unknown>;
    try { body = await req.json(); }
    catch { return reply({ error: "Request data padh nahi paya. Dobara koshish karein.", stage }, 400); }

    const memberId = String(body.member_id || "").trim();
    const password = String(body.password || "");
    if (!memberId) return reply({ error: "Member select nahi hua.", stage }, 400);
    if (password.length < 8) return reply({ error: "Password kam se kam 8 characters ka hona chahiye.", stage }, 400);

    stage = "member record lookup";
    const { data: member, error: memberError } = await admin
      .from("members")
      .select("id, full_name, mobile, active, auth_user_id")
      .eq("id", memberId)
      .maybeSingle();

    if (memberError) {
      console.error("members lookup failed:", memberError.message);
      return reply({ error: "Supabase ke members record mein dikkat: " + memberError.message, stage }, 500);
    }
    if (!member || member.active === false) {
      return reply({ error: "Is Member ka active Supabase record nahi mila. Member ka record pehle sync/check karna hoga.", stage }, 404);
    }

    stage = "member mobile number check";
    const rawPhone = String(member.mobile || "").trim();
    const phone = rawPhone.replace(/[^\\d+]/g, "");
    if (!/^\\+[1-9][0-9]{7,14}$/.test(phone)) {
      return reply({
        error: "Member ka Supabase mobile number country code ke saath hona chahiye. Abhi saved number: " + (rawPhone || "khali"),
        stage,
      }, 400);
    }

    stage = "existing member account check";
    let userId: string | null = member.auth_user_id || null;
    let existingUser: any = null;

    if (userId) {
      const { data, error } = await admin.auth.admin.getUserById(userId);
      if (error || !data.user) {
        console.error("linked auth user lookup failed:", error?.message);
        return reply({ error: "Is Member se juda purana Login account nahi mila. Support ki zaroorat hai.", stage }, 409);
      }
      existingUser = data.user;
    } else {
      let page = 1;
      while (!existingUser && page <= 10) {
        const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 100 });
        if (error) {
          console.error("Auth user search failed:", error.message);
          return reply({ error: "Purana Member Login check nahi ho paya: " + error.message, stage }, 500);
        }
        existingUser = data.users.find((u) => u.phone === phone) || null;
        if (data.users.length < 100) break;
        page++;
      }
      if (existingUser) {
        const { data: linked, error: linkedError } = await admin
          .from("members").select("id").eq("auth_user_id", existingUser.id).maybeSingle();
        if (linkedError) {
          console.error("member account link check failed:", linkedError.message);
          return reply({ error: "Purane Login ka link check nahi hua: " + linkedError.message, stage }, 500);
        }
        if (linked && linked.id !== memberId) {
          return reply({ error: "Yeh mobile number kisi doosre Member ke Login se juda hua hai.", stage }, 409);
        }
        userId = existingUser.id;
      }
    }

    stage = existingUser ? "existing account password update" : "new account creation";
    if (userId) {
      const { error } = await admin.auth.admin.updateUserById(userId, {
        password,
        phone,
        phone_confirm: true,
        user_metadata: { role: "member", member_name: member.full_name },
      });
      if (error) {
        console.error("Auth password update failed:", error.message);
        return reply({ error: "Member password update nahi hua: " + error.message, stage }, 400);
      }
    } else {
      const { data, error } = await admin.auth.admin.createUser({
        phone,
        password,
        phone_confirm: true,
        user_metadata: { role: "member", member_name: member.full_name },
      });
      if (error) {
        console.error("Auth account creation failed:", error.message);
        return reply({ error: "Member ka Login create nahi hua: " + error.message, stage }, 400);
      }
      userId = data.user.id;
    }

    stage = "member account linking";
    const { error: linkError } = await admin.from("members")
      .update({ auth_user_id: userId }).eq("id", memberId);
    if (linkError) {
      console.error("members auth_user_id update failed:", linkError.message);
      return reply({ error: "Login ban gaya, lekin Member record se link nahi hua: " + linkError.message, stage }, 500);
    }

    const { error: profileUpsertError } = await admin.from("user_profiles").upsert({
      user_id: userId,
      role: "member",
      display_name: member.full_name,
    }, { onConflict: "user_id" });
    if (profileUpsertError) {
      console.error("user_profiles upsert failed:", profileUpsertError.message);
      return reply({ error: "Login ban gaya, lekin Member profile save nahi hui: " + profileUpsertError.message, stage }, 500);
    }

    return reply({
      success: true,
      member_name: member.full_name,
      phone,
      updated: !!existingUser,
      message: existingUser ? "Member ka password update ho gaya." : "Member ka Login ban gaya.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("admin-create-member failed at " + stage + ":", message);
    return reply({ error: "Kaam is jagah ruk gaya: " + stage + ". " + message, stage }, 500);
  }
});
