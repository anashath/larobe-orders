// Supabase Edge Function: notify-order
//
// Called by the client right after an order (or its status) is saved.
// Looks up every push subscription for the target role(s) and sends each
// one a Web Push notification via VAPID. Runs with the service_role key
// so it can read push_subscriptions across all users (bypassing RLS).
//
// Deploy:   supabase functions deploy notify-order
// Secrets:  supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... VAPID_SUBJECT=mailto:you@example.com
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@example.com";

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { roles, title, body, url } = await req.json();
    if (!Array.isArray(roles) || !roles.length || !title) {
      return new Response(JSON.stringify({ error: "roles[] and title are required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/push_subscriptions?role=in.(${roles.join(",")})&select=id,endpoint,p256dh,auth`,
      {
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      }
    );
    const subs: { id: number; endpoint: string; p256dh: string; auth: string }[] = await res.json();

    const payload = JSON.stringify({ title, body: body || "", url: url || "/larobe-orders/index.html" });

    const results = await Promise.allSettled(
      subs.map((s) =>
        webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload
        )
      )
    );

    // Prune subscriptions the push service reports as dead (410 Gone / 404),
    // otherwise every send keeps retrying an endpoint that will never work again.
    const deadIds: number[] = [];
    results.forEach((r, i) => {
      if (r.status === "rejected") {
        const statusCode = (r.reason && (r.reason.statusCode || r.reason.status)) || null;
        if (statusCode === 410 || statusCode === 404) deadIds.push(subs[i].id);
      }
    });
    if (deadIds.length) {
      await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?id=in.(${deadIds.join(",")})`, {
        method: "DELETE",
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      });
    }

    return new Response(
      JSON.stringify({ sent: results.filter((r) => r.status === "fulfilled").length, total: subs.length }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
