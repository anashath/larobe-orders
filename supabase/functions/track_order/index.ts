// Supabase Edge Function: track_order
//
// Public, unauthenticated endpoint. Given an order id + the phone number
// used at checkout, returns status ONLY — no customer details, no prices,
// no items (HANDOFF.md §6: "order number + phone -> status only"). Wrong
// phone or nonexistent/other-tenant order both return the same generic
// "not found" response, so this can't be used to enumerate order ids or
// leak whether an id is valid.
//
// Deploy: supabase functions deploy track_order
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const serviceHeaders = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
};

function normalizePhone(phone: string): string {
  return phone.replace(/[\s-]/g, "").replace(/^\+?960/, "");
}

function notFound() {
  return new Response(JSON.stringify({ error: "No matching order found" }), {
    status: 404,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const url = new URL(req.url);
    const tenantSlug = url.searchParams.get("tenant_slug");
    const orderId = url.searchParams.get("order_id");
    const phone = url.searchParams.get("phone");

    if (!tenantSlug || !orderId || !phone) {
      return new Response(
        JSON.stringify({ error: "tenant_slug, order_id, and phone are all required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const tenantRes = await fetch(
      `${SUPABASE_URL}/rest/v1/tenants?slug=eq.${encodeURIComponent(tenantSlug)}&active=eq.true&select=id`,
      { headers: serviceHeaders }
    );
    const tenants = await tenantRes.json();
    const tenant = tenants[0];
    if (!tenant) return notFound();

    const orderRes = await fetch(
      `${SUPABASE_URL}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}&tenant_id=eq.${tenant.id}` +
        `&select=status,contact,order_date`,
      { headers: serviceHeaders }
    );
    const orders = await orderRes.json();
    const order = orders[0];
    if (!order) return notFound();

    if (normalizePhone(order.contact ?? "") !== normalizePhone(phone)) return notFound();

    return new Response(
      JSON.stringify({ status: order.status, order_date: order.order_date }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
