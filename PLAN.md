# Plan: livepeer-studio → Design System → Explorer → Website Link

## Revised Priority Order

1. **livepeer-studio** — developer dashboard (new repo, reuse NAAP components)
2. **@livepeer/ui** — extract design system package from NAAP
3. **Explorer** — update with design system (lower priority)
4. **Website** — add App button linking to Studio + Explorer

---

## What NAAP Gives Us (Audit Results)

### Components Ready to Reuse (18 total from `@naap/ui`)
| Category | Components |
|----------|-----------|
| Layout | Card, Modal |
| Data | Badge, Stat, VersionBadge, DataTable, Tooltip, ReleaseNotesViewer |
| Forms | Button, Input, Textarea, Select, Label, SearchInput, FilterBar, Toggle, Tabs |
| Feedback | EmptyState, LoadingState, LoadingSpinner, Skeleton, SkeletonCard, ConfirmDialog |

### Theme Tokens (`@naap/theme`)
- **Colors**: Dark surfaces (#121212, #1A1A1A, #222222), 6-level text hierarchy, brand green (#18794E/#1E9960), accent palette (blue, amber, rose, purple)
- **Typography**: Inter + JetBrains Mono, 7-step type scale (display → label)
- **Spacing**: 4px–48px scale
- **Motion**: 4 timing presets + easing curves
- **Dark mode**: class-based via CSS custom properties

### Why Extraction Is Easy
- 100% Tailwind utility classes — no CSS-in-JS lock-in
- Components don't import icons directly (passed as props)
- No Framer Motion in `@naap/ui` itself (only at app level)
- Theme is pure TypeScript exports + CSS variables
- No monorepo-specific coupling

---

## Phase 1: Create `livepeer-studio` Repo

**New repo.** Developer-focused dashboard for Livepeer Gateway API.

### Stack
- Next.js 15, React 19, Tailwind v4, TypeScript
- Copy NAAP's `@naap/ui` components directly into `src/components/ui/`
- Copy NAAP's `@naap/theme` tokens into `src/styles/`
- Adapt globals.css with NAAP's CSS variable system

### Core Pages
| Page | Description | NAAP Components Used |
|------|------------|---------------------|
| **Dashboard** | API usage stats, recent streams, quick actions | Card, Stat, Badge, DataTable |
| **API Keys** | Create/manage/revoke keys | Card, Button, Input, Modal, ConfirmDialog |
| **Streams** | Create stream, list active/past, stream detail | DataTable, Badge, SearchInput, FilterBar, Tabs |
| **Assets** | Upload, transcode, manage video assets | DataTable, Card, EmptyState, LoadingState |
| **Multistream** | Configure multistream targets | Card, Input, Select, Toggle, Button |
| **Webhooks** | Configure event webhooks | DataTable, Card, Modal, Input |
| **Usage & Billing** | Usage metrics, billing info | Card, Stat, Tabs |
| **Settings** | Account, team management | Card, Input, Tabs, Toggle |

### Layout
- **Sidebar nav** (adapt from NAAP's web-next sidebar pattern)
- **Top bar** with workspace/team context
- **Dark mode default** (same as NAAP)

### Data Layer
- Livepeer Gateway API (REST)
- Auth: API key-based initially

### Steps
1. Create repo, scaffold Next.js 15
2. Copy `packages/ui/src/*.tsx` → `src/components/ui/`
3. Copy `packages/theme/src/` → `src/styles/theme/`
4. Set up globals.css with NAAP's CSS variable definitions
5. Set up Tailwind config extending NAAP theme tokens
6. Build sidebar layout shell
7. Build pages one by one (Dashboard first, then API Keys, Streams, etc.)
8. Connect to Gateway API

**Deliverable:** Working developer dashboard at studio.livepeer.org

---

## Phase 2: Extract `@livepeer/ui` Design System Package

**After Studio is working**, extract the shared pieces into a proper package.

### What Goes In
1. **`@livepeer/tokens`** — theme values (colors, type, spacing, motion, border radius)
   - TypeScript exports
   - CSS custom properties
   - Tailwind preset (`require('@livepeer/tokens/tailwind')`)

2. **`@livepeer/ui`** — React component library
   - All 18 components from NAAP
   - Built to ESM/CJS with type definitions (tsup)
   - Peer deps: React 19, Tailwind v4
   - Optional peer dep: Framer Motion, Lucide React

### Package Structure
```
@livepeer/ui/
├── src/
│   ├── components/    (Button, Card, Modal, DataTable, etc.)
│   ├── tokens/        (colors, typography, spacing, motion)
│   ├── globals.css    (CSS variables + base utilities)
│   └── tailwind.ts    (shared Tailwind config preset)
├── package.json
└── tsup.config.ts     (build ESM + CJS + types)
```

### Steps
1. Create package (can be in NAAP monorepo or standalone repo)
2. Move components from NAAP `packages/ui` → new package
3. Add tsup build (ESM + CJS + .d.ts)
4. Publish to npm as `@livepeer/ui`
5. Update `livepeer-studio` to import from `@livepeer/ui` instead of local copies
6. Update NAAP to import from `@livepeer/ui` (optional, can happen later)

**Deliverable:** Published npm package that Studio and Explorer both consume.

---

## Phase 3: Explorer (Lower Priority)

**New repo** or update existing if one exists.

### Stack
- Same as Studio: Next.js 15, React 19, Tailwind v4
- Imports `@livepeer/ui` (the design system package from Phase 2)

### Core Pages
- Network overview dashboard
- Orchestrators list + detail
- Delegator detail
- Rounds history
- Governance/voting
- Transaction feed

### Data Layer
- Livepeer subgraph (The Graph) for protocol data
- Livepeer API for real-time metrics
- No backend — client-side queries

**Deliverable:** Functional Explorer using shared design system.

---

## Phase 4: Website — Add App Button

**Repo:** `adamsoffer/website`

1. Add "App" button/dropdown to Header nav
   - "Studio" → studio.livepeer.org
   - "Explorer" → explorer.livepeer.org
2. Style matches existing nav pattern

**Deliverable:** Website links to both apps.

---

## Sequencing

```
Phase 1 (Studio)         ──> START NOW
Phase 2 (Design System)  ──> after Studio works, extract shared code
Phase 3 (Explorer)       ──> after design system published
Phase 4 (Website link)   ──> after both apps are live
```

---

## What We're NOT Doing

- **No Stitches** — clean break, Tailwind v4 only
- **No premature abstraction** — copy first, extract when we know what's shared
- **No NAAP runtime dependency** — Studio/Explorer are standalone apps
- **No Storybook yet** — build it when the design system is extracted (Phase 2)
- **No monorepo** for website/studio/explorer

---

## Open Questions

1. **Studio URL**: studio.livepeer.org?
2. **Auth for Studio**: API key only? Or OAuth/Clerk?
3. **Gateway API base URL**: Which environment?
4. **Explorer URL**: explorer.livepeer.org?
5. **Repo org**: `livepeer/studio` and `livepeer/explorer`? Or under `adamsoffer/`?
6. **Design system package scope**: `@livepeer/ui` or different npm scope?
