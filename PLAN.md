# Plan: Website + Explorer + Studio (Separate Repos, Aligned Styling)

## Context

- **Website** (`adamsoffer/website`) already exists — Next.js 15, Tailwind v4, Favorit Pro, Holographik visual language
- **NAAP** (`naap/`) is the platform monorepo — has web-next shell, workflow apps, plugin system, shared `@naap/theme` + `@naap/ui`
- **Explorer** and **Studio** don't exist yet
- Goal: website gets an "App" button linking to Explorer/Studio, then we build those apps with styling that aligns with website. Later extract shared design system — not now.

## Architecture Decision

**Separate repos.** No monorepo for website/explorer/studio.

- `adamsoffer/website` — marketing site (already exists)
- `livepeer/explorer` — new repo, protocol explorer
- `livepeer/studio` — new repo, creator/developer tool

NAAP stays as the platform infra monorepo. Explorer and Studio are standalone consumer apps.

---

## Phase 1: Website — Add "App" Button + Polish

**Repo:** `adamsoffer/website`

1. Add "App" dropdown/button to Header nav
   - "Explorer" links to explorer URL (placeholder initially, e.g. explorer.livepeer.org)
   - "Studio" links to studio URL (placeholder initially, e.g. studio.livepeer.org)
   - Style: matches existing nav pattern (see Header.tsx dropdown system)
2. Ensure homepage sections are complete per the brief
3. No design system extraction — just ship the site

**Deliverable:** Website live with App button pointing to Explorer and Studio.

---

## Phase 2: Explorer — New Repo, New Styling

**Repo:** `livepeer/explorer` (new)

**Stack:** Next.js 15, React 19, Tailwind v4, TypeScript

1. Scaffold Next.js 15 app
2. **Copy styling approach from website** (not import — just align):
   - Same `globals.css` pattern with `@theme` tokens (colors, type scale)
   - Same color palette: `#121212` dark, `#18794E` green accent, green/blue families
   - Same typography: Favorit Pro + Favorit Mono (same weights, same line heights)
   - Same dark surface scale, text opacity hierarchy
   - Same animation conventions (Framer Motion `whileInView`, `prefers-reduced-motion`)
3. Build core Explorer pages:
   - **Home/Dashboard** — network overview (orchestrators, stake, rounds, inflation)
   - **Orchestrators list** — sortable table, performance scores, fees
   - **Orchestrator detail** — delegators, reward history, commission rates
   - **Delegator detail** — stake, rewards, delegation history
   - **Rounds** — round history, participation
   - **Transactions** — recent protocol transactions
   - **Voting/Governance** — active proposals, voting status
4. Data layer:
   - Livepeer subgraph (The Graph) for protocol data
   - Livepeer API for real-time orchestrator metrics
   - No backend needed initially — all client-side subgraph queries
5. Shared layout:
   - Header with Livepeer logo + nav + link back to website
   - Same footer pattern as website
   - Container component (max-w-7xl)

**Deliverable:** Functional Explorer with visual alignment to website.

---

## Phase 3: Studio — New Repo, New Styling

**Repo:** `livepeer/studio` (new)

**Stack:** Next.js 15, React 19, Tailwind v4, TypeScript

1. Scaffold Next.js 15 app
2. **Same styling alignment as Explorer** — copy the `globals.css` theme tokens
3. Build core Studio pages:
   - **Dashboard** — API usage overview, recent streams, quick actions
   - **API Keys** — create/manage/revoke keys
   - **Streams** — create stream, list active/past streams, stream detail
   - **Assets** — upload, transcode, manage video assets
   - **Multistream** — configure multistream targets
   - **Webhooks** — configure event webhooks
   - **Usage & Billing** — usage metrics, billing info
   - **Settings** — account, team management
4. Data layer:
   - Livepeer Gateway API (REST) for all operations
   - Auth: API key or OAuth (TBD based on Gateway auth model)
5. Same shared layout patterns (header, footer, container)

**Deliverable:** Functional Studio with visual alignment to website and Explorer.

---

## Phase 4: Extract Design System (Later)

**Only after Website + Explorer + Studio are shipped and stable.**

1. Identify what's actually shared (not hypothetically shared):
   - Token values (colors, type, spacing, motion)
   - Common components (Button, Card, Container, Badge, Input, etc.)
   - Layout patterns (Header, Footer)
2. Create `@livepeer/design-tokens` package
   - Raw values only — not framework-specific
   - Consumed via Tailwind config extension in each app
3. Create `@livepeer/ui` package (optional, only if enough overlap)
   - React components that all three apps actually use
   - Published to npm, each app pins a version
4. Each app migrates from copy-pasted tokens to the package at its own pace

---

## What We're NOT Doing

- **No monorepo** for website/explorer/studio
- **No shared package upfront** — copy the tokens, move fast, extract later
- **No NAAP dependency** — Explorer and Studio are standalone. They don't import from NAAP packages.
- **No Stitches** — clean break, Tailwind v4 everywhere
- **No over-abstraction** — three apps with the same `globals.css` theme is fine for now

---

## Sequencing

```
Phase 1 (Website)  ──> can start now
Phase 2 (Explorer) ──> can start in parallel with Phase 1
Phase 3 (Studio)   ──> can start after Explorer patterns established
Phase 4 (Design System) ──> after all three are stable
```

Explorer and Studio can share a lot of scaffolding since they're both Next.js 15 + Tailwind v4. Once Explorer is set up, Studio copies its foundation.

---

## Open Questions

1. **Explorer URL**: explorer.livepeer.org? Or a subpath?
2. **Studio URL**: studio.livepeer.org?
3. **Auth for Studio**: What auth system? (Clerk, NextAuth, custom?)
4. **Explorer data**: Existing subgraph endpoints or new ones?
5. **Repo org**: `livepeer/explorer` and `livepeer/studio`? Or under `adamsoffer/`?
