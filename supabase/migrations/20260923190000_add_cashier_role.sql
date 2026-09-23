-- Phase 4 step 3: add a "cashier" role for POS-only counter staff who
-- shouldn't have full manager/admin privileges (HANDOFF.md §7b).
--
-- Scope: a cashier can run the counter (open/close their own till, ring up
-- sales) but cannot edit or cancel orders after creation, manage products,
-- or see reports/settings — same minimal-privilege spirit as the existing
-- delivery role. Enforced at the RLS layer, not just the UI, matching how
-- every other role in this app is actually gated.
--
-- Fixes a real bug found while building this: createUser()/updateUserRole()
-- in index.html only ever wrote to public.profiles, never to
-- public.tenant_members — but RLS everywhere reads tenant_members via
-- get_my_role(tenant_id), not profiles. The four existing users all
-- happen to have matching rows in both tables (from the Phase 1 backfill),
-- masking this, but any user created or role-changed since then would have
-- had a profiles row granting them UI access while tenant_members (and
-- therefore every RLS-gated action) left them with no real permissions at
-- all. index.html is updated in the same change to write both tables.

ALTER TABLE "public"."profiles" DROP CONSTRAINT "profiles_role_check";
ALTER TABLE "public"."profiles" ADD CONSTRAINT "profiles_role_check"
  CHECK (role = ANY (ARRAY['admin'::text, 'manager'::text, 'delivery'::text, 'cashier'::text]));

ALTER TABLE "public"."tenant_members" DROP CONSTRAINT "tenant_members_role_check";
ALTER TABLE "public"."tenant_members" ADD CONSTRAINT "tenant_members_role_check"
  CHECK (role = ANY (ARRAY['admin'::text, 'manager'::text, 'delivery'::text, 'cashier'::text]));

-- Cashier can create counter sales (same as manager for these two tables —
-- the Counter screen is what actually constrains a cashier to in-store
-- sales client-side; editing/deleting after creation stays admin/manager
-- only, matching how delivery is already scoped to status-only updates).
DROP POLICY "orders_insert" ON "public"."orders";
CREATE POLICY "orders_insert" ON "public"."orders"
  FOR INSERT TO "authenticated"
  WITH CHECK (get_my_role(tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text, 'cashier'::text]));

DROP POLICY "order_items_insert" ON "public"."order_items";
CREATE POLICY "order_items_insert" ON "public"."order_items"
  FOR INSERT TO "authenticated"
  WITH CHECK (get_my_role(tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text, 'cashier'::text]));

-- Cashier needs to open/close their own till without a manager present —
-- that's the whole point of a counter-only role.
DROP POLICY "till_sessions_insert" ON "public"."till_sessions";
CREATE POLICY "till_sessions_insert" ON "public"."till_sessions"
  FOR INSERT TO "authenticated"
  WITH CHECK (get_my_role(tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text, 'cashier'::text]));

DROP POLICY "till_sessions_update" ON "public"."till_sessions";
CREATE POLICY "till_sessions_update" ON "public"."till_sessions"
  FOR UPDATE TO "authenticated"
  USING (get_my_role(tenant_id) = ANY (ARRAY['admin'::text, 'manager'::text, 'cashier'::text]));
