-- Phase 1 step 3: add tenant_id to every business table, backfilled to
-- La Robe (the only tenant that exists today), then enforced NOT NULL.
--
-- profiles is deliberately excluded: it's global user identity, not
-- per-tenant data. Per-tenant role assignment moves to tenant_members
-- in the next migration (step 4), which replaces profiles.role.

DO $$
DECLARE
  la_robe_id uuid := 'aca3f6c5-62aa-4efc-824f-75f0d65bafcd';
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'expense_activity', 'expenses', 'gst_rate_history', 'order_activity',
    'order_item_history', 'order_items', 'orders', 'product_activity',
    'products', 'push_subscriptions', 'stock_entries', 'stock_movements'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN tenant_id uuid', t);
    EXECUTE format('UPDATE public.%I SET tenant_id = %L', t, la_robe_id);
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN tenant_id SET NOT NULL', t);
    EXECUTE format(
      'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (tenant_id) REFERENCES public.tenants(id)',
      t, t || '_tenant_id_fkey'
    );
    EXECUTE format('CREATE INDEX %I ON public.%I (tenant_id)', t || '_tenant_id_idx', t);
  END LOOP;
END $$;

-- app_settings is a key/value table with `key` as the sole primary key
-- today. Under multi-tenancy each tenant needs its own settings, so the
-- primary key becomes (tenant_id, key) instead of just key.
ALTER TABLE "public"."app_settings" ADD COLUMN "tenant_id" uuid;
UPDATE "public"."app_settings" SET "tenant_id" = 'aca3f6c5-62aa-4efc-824f-75f0d65bafcd';
ALTER TABLE "public"."app_settings" ALTER COLUMN "tenant_id" SET NOT NULL;
ALTER TABLE "public"."app_settings"
  ADD CONSTRAINT "app_settings_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES "public"."tenants"(id);
ALTER TABLE "public"."app_settings" DROP CONSTRAINT "app_settings_pkey";
ALTER TABLE "public"."app_settings" ADD CONSTRAINT "app_settings_pkey" PRIMARY KEY (tenant_id, key);

-- Composite indexes for the hottest query patterns (tenant-scoped listing
-- ordered/filtered by a second column), beyond the plain tenant_id indexes
-- created above.
CREATE INDEX "orders_tenant_id_created_at_idx" ON "public"."orders" (tenant_id, created_at);
CREATE INDEX "products_tenant_id_active_idx" ON "public"."products" (tenant_id, active);
