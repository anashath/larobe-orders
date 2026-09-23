-- Phase 4 step 1: schema for POS mode (HANDOFF.md §7b).
--
-- 1. products.barcode: lookup key for the counter-checkout screen's
-- barcode/SKU scan input. Nullable (not every product will have a barcode
-- assigned immediately) and unique per tenant, not globally — two
-- different tenants could legitimately use the same barcode scheme.
ALTER TABLE "public"."products" ADD COLUMN "barcode" text;
CREATE UNIQUE INDEX "products_tenant_barcode_idx" ON "public"."products" (tenant_id, barcode) WHERE barcode IS NOT NULL;

-- 2. till_sessions: one row per open/close cycle of a physical till.
-- Counter sales require an open till (enforced in the app, not here) so
-- every counter sale is attributable to a session for cash reconciliation.
-- expected_cash/variance are computed and stored at close time rather than
-- derived on the fly, so a closed session's numbers don't silently drift
-- if orders are edited afterward.
CREATE TABLE "public"."till_sessions" (
  "id"                    bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "tenant_id"             uuid                     NOT NULL REFERENCES "public"."tenants"(id),
  "opened_by"             uuid                     NOT NULL,
  "opened_by_name"        text,
  "opened_at"             timestamp with time zone NOT NULL DEFAULT now(),
  "opening_cash"          numeric                  NOT NULL DEFAULT 0,
  "closed_by"             uuid,
  "closed_by_name"        text,
  "closed_at"             timestamp with time zone,
  "closing_cash_counted"  numeric,
  "expected_cash"         numeric,
  "variance"              numeric,
  "status"                text                     NOT NULL DEFAULT 'open',
  CONSTRAINT "till_sessions_pkey" PRIMARY KEY (id),
  CONSTRAINT "till_sessions_status_check" CHECK (status = ANY (ARRAY['open'::text, 'closed'::text]))
);

CREATE INDEX "till_sessions_tenant_status_idx" ON "public"."till_sessions" (tenant_id, status);

ALTER TABLE "public"."till_sessions" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "till_sessions_select" ON "public"."till_sessions"
  FOR SELECT TO "authenticated"
  USING (get_my_role(tenant_id) IS NOT NULL);

CREATE POLICY "till_sessions_insert" ON "public"."till_sessions"
  FOR INSERT TO "authenticated"
  WITH CHECK (get_my_role(tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text]));

CREATE POLICY "till_sessions_update" ON "public"."till_sessions"
  FOR UPDATE TO "authenticated"
  USING (get_my_role(tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text]));

-- 3. orders.till_session_id: ties a counter sale to the till session it
-- was rung up under, for cash reconciliation. Nullable — only counter
-- (in_store, POS-mode) sales set it; web and manually-entered orders don't
-- belong to a till.
ALTER TABLE "public"."orders" ADD COLUMN "till_session_id" bigint REFERENCES "public"."till_sessions"(id);
