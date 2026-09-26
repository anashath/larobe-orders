-- Phase 5.2: self-service store branding — logo storage.
--
-- Public bucket (the storefront needs to render a logo with no auth), but
-- writes are restricted to the ADMIN of the tenant named in the path's first
-- folder segment (<tenant_id>/<file>), same convention as product-images.
-- Deliberately narrower than product-images (any active member): branding is
-- an admin decision, matching tenants_update_admin on the branding column.
--
-- Bucket-level limits are the real enforcement, not the admin app's client-side
-- checks: 1 MB, png/jpeg/webp only. SVG is excluded on purpose — an SVG opened
-- directly can run script on the storage origin, and a tenant admin shouldn't be
-- able to publish that.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('tenant-logos', 'tenant-logos', true, 1048576, ARRAY['image/png','image/jpeg','image/webp'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "tenant_logos_public_read" ON "storage"."objects"
  FOR SELECT
  USING (bucket_id = 'tenant-logos');

CREATE POLICY "tenant_logos_admin_insert" ON "storage"."objects"
  FOR INSERT TO "authenticated"
  WITH CHECK (
    bucket_id = 'tenant-logos'
    AND EXISTS (SELECT 1 FROM public.tenant_members tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id::text = (storage.foldername(name))[1]
        AND tm.active AND tm.role = 'admin')
  );

CREATE POLICY "tenant_logos_admin_update" ON "storage"."objects"
  FOR UPDATE TO "authenticated"
  USING (
    bucket_id = 'tenant-logos'
    AND EXISTS (SELECT 1 FROM public.tenant_members tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id::text = (storage.foldername(name))[1]
        AND tm.active AND tm.role = 'admin')
  );

CREATE POLICY "tenant_logos_admin_delete" ON "storage"."objects"
  FOR DELETE TO "authenticated"
  USING (
    bucket_id = 'tenant-logos'
    AND EXISTS (SELECT 1 FROM public.tenant_members tm
      WHERE tm.user_id = auth.uid()
        AND tm.tenant_id::text = (storage.foldername(name))[1]
        AND tm.active AND tm.role = 'admin')
  );
