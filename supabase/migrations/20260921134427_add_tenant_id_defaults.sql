-- Production-cutover safety net. tenant_id is NOT NULL with no default
-- on every business table (as of the earlier backfill migration) — fine
-- on staging, but risky for production: GitHub Pages auto-deploys
-- index.html straight from `main` the instant phase-1-tenancy merges,
-- so there is no way to apply this migration and merge the tenant_id-
-- aware frontend atomically. Whichever happens first, the live app
-- would break for every insert during the gap.
--
-- Adding a DEFAULT (not removing NOT NULL) closes that gap: the OLD
-- deployed frontend (which doesn't send tenant_id) keeps working via
-- the default, and the NEW frontend (which sends it explicitly) works
-- identically. Both can be live simultaneously with zero race window.
-- The default can be dropped later once the new frontend is confirmed
-- merged and live, if explicit-only inserts are preferred going forward
-- — not urgent, no need to do that as part of this promotion.

DO $$
DECLARE
  la_robe_id uuid := 'aca3f6c5-62aa-4efc-824f-75f0d65bafcd';
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'app_settings', 'expense_activity', 'expenses', 'gst_rate_history',
    'order_activity', 'order_item_history', 'order_items', 'orders',
    'product_activity', 'products', 'push_subscriptions', 'stock_entries',
    'stock_movements'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN tenant_id SET DEFAULT %L', t, la_robe_id);
  END LOOP;
END $$;
