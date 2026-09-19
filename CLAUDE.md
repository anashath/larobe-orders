# larobe-orders

Full project plan, decisions, and current status live in [`HANDOFF.md`](../HANDOFF.md) on the Desktop (one level up from this repo). **Read that file first in any new session** — this file only holds facts a session needs immediately; HANDOFF.md is the source of truth for status and decisions.

## What this repo is

Two things share this repo, on different branches:
- **The live admin app** (`index.html`, `feature/order-flags` and other feature branches): La Robe Maldives' revenue-generating internal Orders PWA. Do not break this.
- **The multi-tenant platform conversion** (`chore/supabase-baseline` and future `phase-*` branches): converting this same Supabase project into a multi-tenant SaaS backend, with La Robe as tenant #1.

## Non-negotiable rules

1. Never modify production directly — all schema changes are migration files in `supabase/migrations/`, tested on staging first.
2. The live admin app must keep working at every step of the conversion.
3. RLS on every table — tenant isolation enforced at the database layer, not just the frontend.
4. Never expose to the public: cost prices, stock quantities, expenses, staff data, profit figures.
5. Never trust the cart — prices, promotions, and totals are recalculated server-side.
6. Secrets live in `.env` (git-ignored). Use staging credentials for development. Never commit keys or tokens.
7. Plan before coding: propose a plan for each phase and wait for approval.
8. One phase per branch (e.g. `phase-1-tenancy`); merge to `main` only after review.

## Environment

- Supabase project ref: `oyzfkknoeweafiqirurv` (production). Staging project not yet created.
- Local tooling (Node LTS, Supabase CLI, Docker Desktop) already installed on this machine as of 2026-09-19.
- `supabase link` already points this repo at production — be deliberate before running anything that writes to it.

## After doing meaningful work here

Update `HANDOFF.md` (§11 "Where we are now") with what changed — don't leave it stale. That file is what lets a future session (or a different person) pick this up without re-deriving context.
