-- Storefront home page redesign (new "La Robe Web Layout" design, 2026-09-23):
-- the "Shop by style" section needs a real, filterable product sub-type
-- (Shoulder / Tote / Moon / Crossbody) distinct from the existing
-- `category` column (which is just 'bags' for everything today). Previously
-- this was only embedded in free-text product names.
--
-- Backfilled from each existing product's name by keyword match, verified
-- against the full active product list before writing this migration —
-- every row's inferred style matches a manual read of its name. Crossbody
-- checked before shoulder/moon/tote since a few names mention more than one
-- (e.g. "Single-shoulder Crossbody ... Bag" is a crossbody bag, not a
-- shoulder bag). Default 'Shoulder' for new rows and the one name with no
-- style keyword at all ("Armpit bag stone pattern" is handled explicitly
-- as Crossbody instead, since an armpit/underarm bag is worn crossbody-style).

ALTER TABLE "public"."products" ADD COLUMN "style" text NOT NULL DEFAULT 'Shoulder';

UPDATE "public"."products" SET "style" = CASE
  WHEN name ILIKE '%crossbody%' THEN 'Crossbody'
  WHEN name ILIKE '%moon%' THEN 'Moon'
  WHEN name ILIKE '%tote%' OR name ILIKE '%toye%' THEN 'Tote'
  WHEN name ILIKE '%shoulder%' THEN 'Shoulder'
  WHEN name ILIKE '%armpit%' THEN 'Crossbody'
  ELSE 'Shoulder'
END;
