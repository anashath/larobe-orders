-- Phase 1 step 4: tenant_members holds per-tenant role assignments,
-- replacing the global role on profiles. profiles.role and the existing
-- 0-arg get_my_role() are left untouched here so current RLS policies
-- (which all call get_my_role() with no args) keep working unchanged —
-- they get rewritten against tenant_members in the next migration
-- (step 5). This migration only adds new things, breaks nothing.

CREATE TABLE "public"."tenant_members" (
  "tenant_id"  uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "role"       text                     NOT NULL,
  "active"     boolean                  NOT NULL DEFAULT true,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "tenant_members_pkey" PRIMARY KEY (tenant_id, user_id),
  CONSTRAINT "tenant_members_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES "public"."tenants"(id),
  CONSTRAINT "tenant_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES "auth"."users"(id),
  CONSTRAINT "tenant_members_role_check" CHECK (role = ANY (ARRAY['admin'::text, 'manager'::text, 'delivery'::text]))
);

CREATE INDEX "tenant_members_user_id_idx" ON "public"."tenant_members" (user_id);

ALTER TABLE "public"."tenant_members"
  ENABLE ROW LEVEL SECURITY;

-- No policies yet, same reasoning as tenants: service-role-only until
-- the RLS rewrite in step 5.

-- Migrate existing staff roles into La Robe's tenant membership.
INSERT INTO "public"."tenant_members" ("tenant_id", "user_id", "role", "active")
SELECT
  'aca3f6c5-62aa-4efc-824f-75f0d65bafcd',
  "id",
  "role",
  COALESCE("is_active", true)
FROM "public"."profiles"
WHERE "role" = ANY (ARRAY['admin'::text, 'manager'::text, 'delivery'::text]);

-- New tenant-aware role lookup, overloaded alongside the existing 0-arg
-- get_my_role() (not replacing it yet). Callers pass the tenant_id of
-- the row they're checking, e.g. USING (get_my_role(orders.tenant_id) = 'admin').
CREATE OR REPLACE FUNCTION "public"."get_my_role"("p_tenant_id" uuid)
  RETURNS text
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  SELECT role FROM public.tenant_members
  WHERE tenant_id = p_tenant_id AND user_id = auth.uid() AND active
  LIMIT 1;
$function$;
