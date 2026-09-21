-- Phase 2 step 4 (place_order): two schema prerequisites.
--
-- 1. orders.source distinguishes web (storefront) from in-store orders —
--    referenced by HANDOFF.md §6 (place_order inserts source='web') and
--    needed by Phase 3's "web order filter" too. Defaults existing rows
--    to 'in_store' since that's what they all are today.
ALTER TABLE "public"."orders" ADD COLUMN "source" text NOT NULL DEFAULT 'in_store';
ALTER TABLE "public"."orders" ADD CONSTRAINT "orders_source_check" CHECK (source = ANY (ARRAY['in_store'::text, 'web'::text]));

-- 2. Private bucket for bank-transfer payment slips. No RLS policy grants
-- anon/authenticated INSERT here on purpose — guests have no auth session
-- to scope an upload policy to safely, so slip uploads are written by the
-- place_order Edge Function using the service role, not directly from the
-- browser. Only tenant staff (admin/manager) can read slips, to verify
-- payments.
INSERT INTO storage.buckets (id, name, public)
VALUES ('payment-slips', 'payment-slips', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "payment_slips_read_staff" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (
    bucket_id = 'payment-slips'
    AND (EXISTS ( SELECT 1 FROM public.tenant_members tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id::text = (storage.foldername(name))[1]
        AND tm.active
        AND tm.role = ANY (ARRAY['admin'::text, 'manager'::text])))
  );
