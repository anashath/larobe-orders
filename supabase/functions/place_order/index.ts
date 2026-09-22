// Supabase Edge Function: place_order
//
// Public, unauthenticated endpoint for the storefront checkout. Never
// trusts client-sent prices — only product_id + quantity are accepted;
// the public.place_order() SQL function looks up current prices/promos/
// stock itself (HANDOFF.md rule 5). This function's job is: resolve the
// tenant, optionally upload a bank-transfer slip to the private
// payment-slips bucket, then call that SQL function via the service role
// (the function refuses to run for any other caller).
//
// Deploy: supabase functions deploy place_order
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const serviceHeaders = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isValidMaldivianPhone(phone: string): boolean {
  // 7 digits, optionally prefixed with +960 / 960
  return /^(\+?960)?\d{7}$/.test(phone.replace(/[\s-]/g, ""));
}

function clientIp(req: Request): string {
  // Supabase's edge runtime sits behind a proxy that sets this; first entry
  // is the original client. Falls back to "unknown" rather than throwing —
  // rate limiting degrades gracefully instead of blocking checkout entirely
  // if the header is ever missing.
  const fwd = req.headers.get("x-forwarded-for");
  return fwd ? fwd.split(",")[0].trim() : "unknown";
}

// Rate limiting: throttles the endpoint itself against repeated calls
// (including failed ones) — distinct from the unpaid-order cap inside
// place_order(), which only counts orders that actually succeeded.
const PHONE_ATTEMPT_LIMIT = 5;
const IP_ATTEMPT_LIMIT = 15;
const ATTEMPT_WINDOW_MINUTES = 10;

async function tooManyAttempts(phone: string, ip: string): Promise<boolean> {
  const since = new Date(Date.now() - ATTEMPT_WINDOW_MINUTES * 60_000).toISOString();

  const [phoneRes, ipRes] = await Promise.all([
    fetch(
      `${SUPABASE_URL}/rest/v1/checkout_attempts?phone=eq.${encodeURIComponent(phone)}&created_at=gte.${since}&select=id&limit=1`,
      { headers: { ...serviceHeaders, Prefer: "count=exact" } }
    ),
    fetch(
      `${SUPABASE_URL}/rest/v1/checkout_attempts?ip=eq.${encodeURIComponent(ip)}&created_at=gte.${since}&select=id&limit=1`,
      { headers: { ...serviceHeaders, Prefer: "count=exact" } }
    ),
  ]);

  const phoneCount = Number(phoneRes.headers.get("content-range")?.split("/")[1] ?? 0);
  const ipCount = Number(ipRes.headers.get("content-range")?.split("/")[1] ?? 0);

  return phoneCount >= PHONE_ATTEMPT_LIMIT || (ip !== "unknown" && ipCount >= IP_ATTEMPT_LIMIT);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "POST only" }, 405);

  try {
    const body = await req.json();
    const { tenant_slug, items, customer, payment, website, elapsed_ms } = body;

    // Bot deterrence, no external service: a hidden field real users never
    // fill (bots that auto-fill every field usually do), and a minimum
    // time between the form rendering and being submitted (faster than any
    // human reading it). Deliberately returns the same generic error as
    // other validation failures, not a distinct "bot detected" message —
    // nothing here should help a script figure out what tripped it.
    const MIN_HUMAN_SUBMIT_MS = 2000;
    if (website || (typeof elapsed_ms === "number" && elapsed_ms < MIN_HUMAN_SUBMIT_MS)) {
      return jsonResponse({ error: "Could not place order. Please try again." }, 400);
    }

    if (!tenant_slug || !Array.isArray(items) || !items.length) {
      return jsonResponse({ error: "tenant_slug and items[] are required" }, 400);
    }
    if (!customer?.name || !customer?.contact) {
      return jsonResponse({ error: "customer.name and customer.contact are required" }, 400);
    }
    if (!isValidMaldivianPhone(customer.contact)) {
      return jsonResponse({ error: "Enter a valid Maldivian phone number" }, 400);
    }
    if (!payment?.method || !["transfer", "cod", "preorder"].includes(payment.method)) {
      return jsonResponse({ error: "payment.method must be transfer, cod, or preorder" }, 400);
    }

    const ip = clientIp(req);
    if (await tooManyAttempts(customer.contact, ip)) {
      return jsonResponse({ error: "Too many attempts. Please wait a few minutes and try again." }, 429);
    }

    // Resolve tenant id (needed for the slip's storage path prefix).
    const tenantRes = await fetch(
      `${SUPABASE_URL}/rest/v1/tenants?slug=eq.${encodeURIComponent(tenant_slug)}&active=eq.true&select=id`,
      { headers: serviceHeaders }
    );
    const tenants = await tenantRes.json();
    const tenant = tenants[0];
    if (!tenant) return jsonResponse({ error: "Tenant not found" }, 404);

    // Log this attempt regardless of what happens next — the throttle
    // check above only reads attempts already logged, so this write
    // happens after, not before.
    await fetch(`${SUPABASE_URL}/rest/v1/checkout_attempts`, {
      method: "POST",
      headers: { ...serviceHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ tenant_id: tenant.id, phone: customer.contact, ip }),
    });

    let slipPath: string | null = null;
    if (payment.method === "transfer" && payment.slip_base64) {
      const bytes = Uint8Array.from(atob(payment.slip_base64), (c) => c.charCodeAt(0));
      const ext = (payment.slip_filename ?? "slip.jpg").split(".").pop();
      slipPath = `${tenant.id}/${Date.now()}.${ext}`;

      const uploadRes = await fetch(
        `${SUPABASE_URL}/storage/v1/object/payment-slips/${slipPath}`,
        {
          method: "POST",
          headers: { ...serviceHeaders, "Content-Type": payment.slip_content_type ?? "image/jpeg" },
          body: bytes,
        }
      );
      if (!uploadRes.ok) {
        return jsonResponse({ error: "Slip upload failed" }, 500);
      }
    }

    const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/place_order`, {
      method: "POST",
      headers: { ...serviceHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({
        p_tenant_slug: tenant_slug,
        p_items: items,
        p_customer_name: customer.name,
        p_customer_contact: customer.contact,
        p_customer_address: customer.address ?? null,
        p_payment_method: payment.method,
        p_amount_paid: payment.amount_paid ?? null,
        p_slip_path: slipPath,
        p_deposit_amount: payment.deposit_amount ?? null,
      }),
    });

    if (!rpcRes.ok) {
      const errBody = await rpcRes.json().catch(() => ({}));
      return jsonResponse({ error: errBody.message ?? "Could not place order" }, 400);
    }

    const result = await rpcRes.json();
    return jsonResponse(result);
  } catch (e) {
    return jsonResponse({ error: String(e) }, 500);
  }
});
