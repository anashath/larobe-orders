-- Completes Phase 1 step 5: tenants and tenant_members themselves never
-- got policies when they were created (steps 2 and 4) — they were
-- explicitly left service-role-only "until the RLS rewrite in step 5",
-- but step 5 only rewrote the OTHER 11 business tables. Without this,
-- nobody but the service role could read their own tenant's info or
-- staff list at all. Tenant creation stays service-role-only (no
-- INSERT/DELETE policies) — matches the manual-approval onboarding
-- decision (Phase 4): tenants are provisioned by Ali, not self-service.

CREATE POLICY "tenants_select_own" ON "public"."tenants"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1 FROM public.tenant_members tm
    WHERE tm.tenant_id = tenants.id AND tm.user_id = auth.uid() AND tm.active)));

CREATE POLICY "tenants_update_admin" ON "public"."tenants"
  FOR UPDATE
  TO "authenticated"
  USING ((public.get_my_role(tenants.id) = 'admin'::text))
  WITH CHECK ((public.get_my_role(tenants.id) = 'admin'::text));

CREATE POLICY "tenant_members_select_own_or_admin" ON "public"."tenant_members"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = auth.uid()) OR (public.get_my_role(tenant_members.tenant_id) = 'admin'::text)));

CREATE POLICY "tenant_members_insert_admin" ON "public"."tenant_members"
  FOR INSERT
  TO "authenticated"
  WITH CHECK ((public.get_my_role(tenant_members.tenant_id) = 'admin'::text));

CREATE POLICY "tenant_members_update_admin" ON "public"."tenant_members"
  FOR UPDATE
  TO "authenticated"
  USING ((public.get_my_role(tenant_members.tenant_id) = 'admin'::text))
  WITH CHECK ((public.get_my_role(tenant_members.tenant_id) = 'admin'::text));

CREATE POLICY "tenant_members_delete_admin" ON "public"."tenant_members"
  FOR DELETE
  TO "authenticated"
  USING ((public.get_my_role(tenant_members.tenant_id) = 'admin'::text));
