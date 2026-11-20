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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return reply({ error: "Sirf POST request allowed hai." }, 405);
  }

  let stage = "request";

  try {
    const token = (req.headers.get("Authorization") || "")
      .replace(/^Bearer\s+/i, "")
      .trim();

    if (!token) return reply({ error: "Admin login nahi mila." }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!url || !serviceKey) {
      return reply({ error: "Supabase Function secrets adhure hain." }, 500);
    }

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    stage = "admin verification";
    const { data: authData, error: authError } = await admin.auth.getUser(token);

    if (authError || !authData.user) {
      return reply({ error: "Admin session expire ho gaya." }, 401);
    }

    const { data: profile, error: profileError } = await admin
      .from("user_profiles")
      .select("role")
      .eq("user_id", authData.user.id)
      .maybeSingle();

    if (profileError || profile?.role !== "admin") {
      return reply({ error: "Sirf Admin Worker Login bana sakta hai." }, 403);
    }

    const body = await req.json();
    const workerType = String(body.worker_type || "");
    const workerId = String(body.worker_id || "").trim();
    const password = String(body.password || "");

    if (!["farm", "staff", "tempo"].includes(workerType) || !workerId) {
      return reply({ error: "Farm/Tempo Worker select nahi hua." }, 400);
    }

    if (password.length < 8) {
      return reply({ error: "Naya Worker password kam se kam 8 characters ka ho." }, 400);
    }

    stage = "Admin cloud data lookup";

    // Prefer the latest snapshot sent by the authenticated Admin app.
    // This avoids requiring an app_state write or depending on a stale snapshot.
    let d: any = body.admin_data;

    if (!d || typeof d !== "object" || Array.isArray(d)) {
      const { data: state, error: stateError } = await admin
        .from("app_state")
        .select("data")
        .eq("user_id", authData.user.id)
        .maybeSingle();

      if (stateError) {
        return reply({
          error: "Admin cloud data read nahi hua: " + stateError.message,
        }, 500);
      }

      if (!state?.data) {
        return reply({
          error: "Admin ka cloud backup nahi mila. Pehle app sync/backup karein.",
        }, 404);
      }

      d = state.data;
    }

    const worker = workerType === "farm" || workerType === "staff"
      ? (Array.isArray(d.staffWorkers) ? d.staffWorkers : [])
          .find((x: any) => String(x.id) === workerId)
      : (Array.isArray(d.tempo?.workers) ? d.tempo.workers : [])
          .find((x: any) => String(x.id) === workerId);

    if (!worker) {
      return reply({
        error: "Chuna hua Worker Admin ke latest saved record mein nahi mila. Pehle app sync karein.",
      }, 404);
    }

    const name = String(worker.name || "").trim();
    const rawPhone = String(worker.phone || "").trim();
    const phone = rawPhone.replace(/[^\d+]/g, "");

    if (!name) return reply({ error: "Worker ka naam missing hai." }, 400);

    if (!/^\+[1-9][0-9]{7,14}$/.test(phone)) {
      return reply({
        error: "Worker mobile country code ke saath save karein, jaise +61... ya +91...",
      }, 400);
    }

    stage = "existing login lookup";
    let existing: any = null;

    for (let page = 1; page <= 10 && !existing; page++) {
      const { data, error } = await admin.auth.admin.listUsers({
        page,
        perPage: 100,
      });

      if (error) {
        return reply({ error: "Existing login check nahi hua: " + error.message }, 500);
      }

      existing = data.users.find((u) => u.phone === phone) || null;
      if (data.users.length < 100) break;
    }

    let userId = existing?.id || null;

    if (existing) {
      const { data: linked, error: linkedError } = await admin
        .from("worker_accounts")
        .select("id,worker_type,worker_id")
        .eq("auth_user_id", existing.id);

      if (linkedError) {
        return reply({ error: "Purana Worker link check nahi hua: " + linkedError.message }, 500);
      }

      if (!linked || linked.length === 0) {
        // Recover only an orphaned worker account created by this function.
        // Never attach an unlinked member or unrelated Auth account as staff.
        const metadata = existing.user_metadata || {};
        const isOrphanedWorker =
          metadata.account_kind === "worker" &&
          String(metadata.worker_name || "").trim() === name;

        if (!isOrphanedWorker) {
          return reply({
            error: "Yeh mobile pehle se kisi doosre account mein istemal hai. Alag mobile number dein; purana account nahi badla.",
          }, 409);
        }
      } else {
        const conflict = linked.find(
          (x: any) => x.worker_type !== workerType || x.worker_id !== workerId,
        );

        if (conflict) {
          return reply({
            error: "Yeh mobile pehle se kisi doosre Worker record se link hai. Admin se record check karayein.",
          }, 409);
        }
      }
    } else {
      stage = "new login creation";
      const { data, error } = await admin.auth.admin.createUser({
        phone,
        password,
        phone_confirm: true,
        user_metadata: { account_kind: "worker", worker_name: name },
      });

      if (error) {
        return reply({ error: "Worker Login nahi bana: " + error.message }, 400);
      }

      userId = data.user.id;
    }

    stage = "worker account linking";
    const { error: linkError } = await admin.from("worker_accounts").upsert({
      auth_user_id: userId,
      worker_type: workerType,
      worker_id: workerId,
      display_name: name,
      mobile: phone,
      active: true,
    }, { onConflict: "worker_type,worker_id" });

    if (linkError) {
      return reply({
        error: "Login bana, lekin Worker link save nahi hua: " + linkError.message,
      }, 500);
    }

    return reply({
      success: true,
      worker_name: name,
      phone,
      worker_type: workerType,
      reused_existing_login: !!existing,
      message: existing
        ? "Is mobile ka login pehle se hai. Wahi purana password istemal karein; Member login password badla nahi gaya."
        : "Worker Login ban gaya. Ab naya password istemal karein.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("admin-create-worker failed at " + stage + ":", message);
    return reply({ error: "Kaam yahan ruka: " + stage + ". " + message }, 500);
  }
});
