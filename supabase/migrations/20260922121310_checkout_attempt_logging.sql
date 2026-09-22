-- Phase 2 step 6b: attempt-based rate limiting for place_order, distinct
-- from the unpaid-order cap (20260922000000) — that cap only counts
-- orders that actually succeeded; this throttles the endpoint itself
-- against repeated calls (including failed/rejected ones), which is what
-- actually stops someone hammering place_order to probe stock, spam
-- invalid requests, or brute-force something.
--
-- One row logged per place_order call, regardless of outcome. Service-role
-- only, same pattern as tenants/tenant_members when first created — no
-- anon/authenticated policies, nothing but the Edge Function touches this.

CREATE TABLE "public"."checkout_attempts" (
  "id"         bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "tenant_id"  uuid                     REFERENCES "public"."tenants"(id),
  "phone"      text,
  "ip"         text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "checkout_attempts_pkey" PRIMARY KEY (id)
);

CREATE INDEX "checkout_attempts_tenant_phone_idx" ON "public"."checkout_attempts" (tenant_id, phone, created_at);
CREATE INDEX "checkout_attempts_ip_idx" ON "public"."checkout_attempts" (ip, created_at);

ALTER TABLE "public"."checkout_attempts"
  ENABLE ROW LEVEL SECURITY;
-- No policies: service-role only.
