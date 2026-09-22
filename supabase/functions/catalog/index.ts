// Supabase Edge Function: catalog
//
// Public, unauthenticated endpoint for the storefront. Given a tenant slug,
// returns curated tenant branding + active products + promotions — never
// cost prices or exact stock quantities (HANDOFF.md rule 4). Runs with the
// service_role key specifically so it can bypass the tenants/products RLS
// (which requires tenant membership) and hand-pick only public-safe fields
// instead — the anon key can never read tenants/products directly, by
// design (see storefront-platform/CLAUDE.md rule 3).
//
// Deploy: supabase functions deploy catalog
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const serviceHeaders = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
};

type StockStatus = "in_stock" | "low_stock" | "out_of_stock";

function stockStatus(stockQty: number, lowStockThreshold: number): StockStatus {
  if (stockQty <= 0) return "out_of_stock";
  if (stockQty <= lowStockThreshold) return "low_stock";
  return "in_stock";
}

function activePromo(promoPrice: number | null, promoStart: string | null, promoEnd: string | null) {
  if (promoPrice == null) return null;
  const today = new Date().toISOString().slice(0, 10);
  if (promoStart && today < promoStart) return null;
  if (promoEnd && today > promoEnd) return null;
  return { price: promoPrice, ends: promoEnd };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const slug = new URL(req.url).searchParams.get("slug");
    if (!slug) {
      return new Response(JSON.stringify({ error: "slug query param is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const tenantRes = await fetch(
      `${SUPABASE_URL}/rest/v1/tenants?slug=eq.${encodeURIComponent(slug)}&active=eq.true` +
        `&select=id,name,branding,currency,bank_details,preorder_deposit_rule`,
      { headers: serviceHeaders }
    );
    const tenants = await tenantRes.json();
    const tenant = tenants[0];
    if (!tenant) {
      return new Response(JSON.stringify({ error: "Tenant not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const productsRes = await fetch(
      `${SUPABASE_URL}/rest/v1/products?tenant_id=eq.${tenant.id}&active=eq.true` +
        `&select=id,name,color,category,image_url,selling_price,price,stock_qty,low_stock_threshold,promo_price,promo_start,promo_end,created_at`,
      { headers: serviceHeaders }
    );
    const rawProducts = await productsRes.json();

    // "New" is products added in the last 14 days — a simple, data-driven
    // signal rather than a separate flag to maintain.
    const NEW_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
    const now = Date.now();

    const products = rawProducts.map((p: any) => ({
      id: p.id,
      name: p.name,
      color: p.color,
      category: p.category,
      image_url: p.image_url,
      price: p.selling_price ?? p.price,
      stock_status: stockStatus(p.stock_qty ?? 0, p.low_stock_threshold ?? 3),
      promo: activePromo(p.promo_price, p.promo_start, p.promo_end),
      is_new: p.created_at ? now - new Date(p.created_at).getTime() < NEW_WINDOW_MS : false,
    }));

    return new Response(
      JSON.stringify({
        tenant: {
          name: tenant.name,
          branding: tenant.branding,
          currency: tenant.currency,
          bank_details: tenant.bank_details,
          preorder_deposit_rule: tenant.preorder_deposit_rule,
        },
        products,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
