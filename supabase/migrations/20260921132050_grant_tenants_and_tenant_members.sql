-- Fixes a gap from the previous migration: RLS policies were added to
-- tenants and tenant_members, but the underlying table-level GRANTs to
-- anon/authenticated were never added (unlike the 14 original tables,
-- which all have explicit GRANTs from the baseline pull). In Postgres,
-- RLS only restricts access that's already granted at the table level —
-- without this, authenticated gets "permission denied" before RLS is
-- even evaluated. Matches the broad-GRANT-plus-RLS-does-the-real-work
-- convention already used on every other table here.

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
  ON TABLE "public"."tenants" TO "anon", "authenticated", "postgres", "service_role";

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
  ON TABLE "public"."tenant_members" TO "anon", "authenticated", "postgres", "service_role";
