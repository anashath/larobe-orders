-- Phase 1 step 5: rewrite RLS policies to be tenant-aware.
--
-- Pattern: every business-table policy that called public.get_my_role()
-- (0-arg, reads profiles.role globally) is dropped and recreated calling
-- public.get_my_role(<table>.tenant_id) instead (reads tenant_members,
-- scoped to that row's tenant). This is a minimal-diff rewrite — same
-- role logic as before, just tenant-scoped. The old 0-arg get_my_role()
-- is left in place; nothing else references it after this migration
-- except profiles' own policies (profiles stays global, untouched here).
--
-- Out of scope here (deliberately): push_subscriptions (already
-- row-owner-scoped by user_id, no role/tenant check needed).
--
-- Storage (product-images, avatars) IS handled in this migration per
-- explicit decision to do it now rather than defer to Phase 2 — see the
-- STORAGE section at the end. Read access to product-images stays fully
-- public (product photos are meant to be publicly visible on the
-- storefront); only upload/delete become tenant-scoped, requiring
-- objects to live under a `<tenant_id>/...` path prefix. IMPORTANT: the
-- existing admin app does not yet upload to that path convention — this
-- will surface as a real break when the admin app is pointed at staging
-- (workflow step 5) and must be fixed there before Phase 1 can promote
-- to production (see HANDOFF.md).

-- ── app_settings ─────────────────────────────────────────────────────

DROP POLICY "app_settings_select_authenticated" ON "public"."app_settings";
CREATE POLICY "app_settings_select_authenticated" ON "public"."app_settings"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1 FROM public.tenant_members tm
    WHERE tm.tenant_id = app_settings.tenant_id AND tm.user_id = auth.uid() AND tm.active)));

DROP POLICY "app_settings_select" ON "public"."app_settings";
CREATE POLICY "app_settings_select" ON "public"."app_settings"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(app_settings.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "app_settings_update" ON "public"."app_settings";
CREATE POLICY "app_settings_update" ON "public"."app_settings"
  FOR UPDATE
  TO PUBLIC
  USING ((public.get_my_role(app_settings.tenant_id) = 'admin'::text));

DROP POLICY "app_settings_write_admin_only" ON "public"."app_settings";
CREATE POLICY "app_settings_write_admin_only" ON "public"."app_settings"
  FOR ALL
  TO "authenticated"
  USING ((public.get_my_role(app_settings.tenant_id) = 'admin'::text))
  WITH CHECK ((public.get_my_role(app_settings.tenant_id) = 'admin'::text));

-- ── expense_activity ─────────────────────────────────────────────────

DROP POLICY "expense_activity_insert" ON "public"."expense_activity";
CREATE POLICY "expense_activity_insert" ON "public"."expense_activity"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(expense_activity.tenant_id) IS NOT NULL));

DROP POLICY "expense_activity_select" ON "public"."expense_activity";
CREATE POLICY "expense_activity_select" ON "public"."expense_activity"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(expense_activity.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

-- ── expenses ─────────────────────────────────────────────────────────

DROP POLICY "expenses_delete" ON "public"."expenses";
CREATE POLICY "expenses_delete" ON "public"."expenses"
  FOR DELETE
  TO PUBLIC
  USING ((public.get_my_role(expenses.tenant_id) = 'admin'::text));

DROP POLICY "expenses_insert" ON "public"."expenses";
CREATE POLICY "expenses_insert" ON "public"."expenses"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(expenses.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "expenses_select" ON "public"."expenses";
CREATE POLICY "expenses_select" ON "public"."expenses"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(expenses.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "expenses_update" ON "public"."expenses";
CREATE POLICY "expenses_update" ON "public"."expenses"
  FOR UPDATE
  TO PUBLIC
  USING ((public.get_my_role(expenses.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

-- ── gst_rate_history ─────────────────────────────────────────────────

DROP POLICY "gst_rates_insert_admin_only" ON "public"."gst_rate_history";
CREATE POLICY "gst_rates_insert_admin_only" ON "public"."gst_rate_history"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((public.get_my_role(gst_rate_history.tenant_id) = 'admin'::text));

DROP POLICY "gst_rates_select_admin_manager" ON "public"."gst_rate_history";
CREATE POLICY "gst_rates_select_admin_manager" ON "public"."gst_rate_history"
  FOR SELECT
  TO "authenticated"
  USING ((public.get_my_role(gst_rate_history.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

-- ── order_activity ───────────────────────────────────────────────────

DROP POLICY "order_activity_insert" ON "public"."order_activity";
CREATE POLICY "order_activity_insert" ON "public"."order_activity"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(order_activity.tenant_id) IS NOT NULL));

DROP POLICY "order_activity_select" ON "public"."order_activity";
CREATE POLICY "order_activity_select" ON "public"."order_activity"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(order_activity.tenant_id) IS NOT NULL));

-- ── order_item_history ───────────────────────────────────────────────

DROP POLICY "Log item changes" ON "public"."order_item_history";
CREATE POLICY "Log item changes" ON "public"."order_item_history"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(order_item_history.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "View item history" ON "public"."order_item_history";
CREATE POLICY "View item history" ON "public"."order_item_history"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.orders o
  WHERE
    ((o.id = order_item_history.order_id) AND ((public.get_my_role(order_item_history.tenant_id) = 'admin'::text) OR (public.get_my_role(order_item_history.tenant_id) = 'manager'::text) OR ((public.get_my_role(order_item_history.tenant_id) = 'delivery'::text) AND
    (o.delivery = auth.email())))))));

-- ── order_items ──────────────────────────────────────────────────────

DROP POLICY "order_items_delete" ON "public"."order_items";
CREATE POLICY "order_items_delete" ON "public"."order_items"
  FOR DELETE
  TO PUBLIC
  USING ((public.get_my_role(order_items.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "order_items_insert" ON "public"."order_items";
CREATE POLICY "order_items_insert" ON "public"."order_items"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(order_items.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "order_items_select" ON "public"."order_items";
CREATE POLICY "order_items_select" ON "public"."order_items"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(order_items.tenant_id) IS NOT NULL));

-- ── orders ───────────────────────────────────────────────────────────

DROP POLICY "orders_delete" ON "public"."orders";
CREATE POLICY "orders_delete" ON "public"."orders"
  FOR DELETE
  TO PUBLIC
  USING ((public.get_my_role(orders.tenant_id) = 'admin'::text));

DROP POLICY "orders_insert" ON "public"."orders";
CREATE POLICY "orders_insert" ON "public"."orders"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(orders.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "orders_select" ON "public"."orders";
CREATE POLICY "orders_select" ON "public"."orders"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(orders.tenant_id) IS NOT NULL));

DROP POLICY "orders_update_admin" ON "public"."orders";
CREATE POLICY "orders_update_admin" ON "public"."orders"
  FOR UPDATE
  TO PUBLIC
  USING ((public.get_my_role(orders.tenant_id) = 'admin'::text));

DROP POLICY "orders_update_delivery" ON "public"."orders";
CREATE POLICY "orders_update_delivery" ON "public"."orders"
  FOR UPDATE
  TO PUBLIC
  USING (((public.get_my_role(orders.tenant_id) = 'delivery'::text) AND (status = 'packed'::text)))
  WITH CHECK ((status = 'delivered'::text));

DROP POLICY "orders_update_manager" ON "public"."orders";
CREATE POLICY "orders_update_manager" ON "public"."orders"
  FOR UPDATE
  TO PUBLIC
  USING ((public.get_my_role(orders.tenant_id) = 'manager'::text));

-- ── product_activity ─────────────────────────────────────────────────

DROP POLICY "product_activity_insert" ON "public"."product_activity";
CREATE POLICY "product_activity_insert" ON "public"."product_activity"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(product_activity.tenant_id) IS NOT NULL));

DROP POLICY "product_activity_select" ON "public"."product_activity";
CREATE POLICY "product_activity_select" ON "public"."product_activity"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(product_activity.tenant_id) = 'admin'::text));

-- ── products ─────────────────────────────────────────────────────────

DROP POLICY "products_delete" ON "public"."products";
CREATE POLICY "products_delete" ON "public"."products"
  FOR DELETE
  TO PUBLIC
  USING ((public.get_my_role(products.tenant_id) = 'admin'::text));

DROP POLICY "products_insert" ON "public"."products";
CREATE POLICY "products_insert" ON "public"."products"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(products.tenant_id) = 'admin'::text));

DROP POLICY "products_select" ON "public"."products";
CREATE POLICY "products_select" ON "public"."products"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(products.tenant_id) IS NOT NULL));

DROP POLICY "products_update" ON "public"."products";
CREATE POLICY "products_update" ON "public"."products"
  FOR UPDATE
  TO PUBLIC
  USING ((public.get_my_role(products.tenant_id) = 'admin'::text));

-- ── stock_entries ────────────────────────────────────────────────────

DROP POLICY "Deactivate entries" ON "public"."stock_entries";
CREATE POLICY "Deactivate entries" ON "public"."stock_entries"
  FOR UPDATE
  TO PUBLIC
  USING ((public.get_my_role(stock_entries.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])))
  WITH CHECK ((public.get_my_role(stock_entries.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "Log stock entries" ON "public"."stock_entries";
CREATE POLICY "Log stock entries" ON "public"."stock_entries"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(stock_entries.tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text])));

DROP POLICY "View stock entries" ON "public"."stock_entries";
CREATE POLICY "View stock entries" ON "public"."stock_entries"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.products p
  WHERE ((p.id = stock_entries.product_id) AND ((public.get_my_role(stock_entries.tenant_id) = 'admin'::text) OR (public.get_my_role(stock_entries.tenant_id) = 'manager'::text))))));

-- ── stock_movements ──────────────────────────────────────────────────

DROP POLICY "stock_movements_insert" ON "public"."stock_movements";
CREATE POLICY "stock_movements_insert" ON "public"."stock_movements"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((public.get_my_role(stock_movements.tenant_id) IS NOT NULL));

DROP POLICY "stock_movements_select" ON "public"."stock_movements";
CREATE POLICY "stock_movements_select" ON "public"."stock_movements"
  FOR SELECT
  TO PUBLIC
  USING ((public.get_my_role(stock_movements.tenant_id) = 'admin'::text));

-- ── STORAGE: tenant-scope product-images writes ─────────────────────
-- Path convention going forward: product-images/<tenant_id>/<filename>.
-- Read stays fully public (storefront needs to show images with no
-- auth); only upload/delete require the uploader to be an active member
-- of the tenant named in the path's first folder segment.

DROP POLICY "Authenticated upload" ON "storage"."objects";
CREATE POLICY "Authenticated upload" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (
    (bucket_id = 'product-images'::text)
    AND (EXISTS ( SELECT 1 FROM public.tenant_members tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id::text = (storage.foldername(name))[1]
        AND tm.active))
  );

DROP POLICY "Authenticated delete" ON "storage"."objects";
CREATE POLICY "Authenticated delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING (
    (bucket_id = 'product-images'::text)
    AND (EXISTS ( SELECT 1 FROM public.tenant_members tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id::text = (storage.foldername(name))[1]
        AND tm.active))
  );

-- "Public read access" (product-images) and all avatars policies are
-- deliberately untouched: avatars are per-user (folder = auth.uid()),
-- not per-tenant, matching profiles staying global.
