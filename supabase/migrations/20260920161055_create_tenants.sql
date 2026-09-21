-- Phase 1 step 2: tenants table. La Robe's id is fixed so later migrations
-- (tenant_id backfill defaults) can reference it as a literal, identically
-- across staging and production.

CREATE TABLE "public"."tenants" (
  "id"                     uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "slug"                   text                     NOT NULL,
  "name"                   text                     NOT NULL,
  "branding"               jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "currency"               text                     NOT NULL DEFAULT 'MVR',
  "gst_settings"           jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "delivery_zones"         jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "bank_details"           jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "preorder_deposit_rule"  jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "active"                 boolean                  NOT NULL DEFAULT true,
  "created_at"             timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"             timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "tenants_pkey" PRIMARY KEY (id),
  CONSTRAINT "tenants_slug_key" UNIQUE (slug),
  CONSTRAINT "tenants_slug_format" CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

ALTER TABLE "public"."tenants"
  ENABLE ROW LEVEL SECURITY;

-- No policies yet: RLS enabled with zero policies denies all anon/authenticated
-- access by default, so this table is service-role-only until step 5 (RLS
-- rewrite) defines real tenant-membership-based policies.

INSERT INTO "public"."tenants"
  ("id", "slug", "name", "currency", "active")
VALUES
  ('aca3f6c5-62aa-4efc-824f-75f0d65bafcd', 'la-robe', 'La Robe Maldives', 'MVR', true);
