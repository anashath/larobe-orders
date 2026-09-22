-- Storefront UI polish, prerequisite data changes.
--
-- 1. products.category: needed for the mockup's category chips
-- (HANDOFF.md §8). Every existing La Robe product is bag-related
-- (checked: shoulder bags, tote bags, moon bags, crossbody — no
-- wallets or anything else yet), so backfilling to 'bags' is accurate,
-- not a guess. Default 'bags' for new rows too, since that's the
-- entire catalog today; future products can set a different category
-- explicitly once the catalog actually diversifies.
ALTER TABLE "public"."products" ADD COLUMN "category" text NOT NULL DEFAULT 'bags';

-- 2. La Robe's actual brand tokens (HANDOFF.md §8), replacing the
-- empty {} placeholder from Phase 1. Read by the catalog function and
-- applied client-side as CSS custom properties, so a future second
-- tenant gets their own look automatically without code changes.
UPDATE "public"."tenants"
SET "branding" = '{
  "colors": {
    "background": "#f6f3ee",
    "foreground": "#161513",
    "accent": "#b8450f"
  },
  "fonts": {
    "heading": "Fraunces",
    "body": "Karla"
  }
}'::jsonb
WHERE "id" = 'aca3f6c5-62aa-4efc-824f-75f0d65bafcd';
