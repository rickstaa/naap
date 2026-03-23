# Studio — Developer Dashboard for Gateway API

## Context

We audited the NAAP monorepo to identify what's reusable for building a standalone **Studio** app (developer dashboard for the Gateway API). Studio should live in its own repo, NOT inside NAAP.

## What to Reuse from NAAP

### Copy as-is (zero changes needed)

**UI Components** — `packages/ui/src/` (~1,700 lines, 18 components)
All components are pure React + Tailwind with no `@naap/*` imports:
- **Layout:** Card, Modal, ConfirmDialog, Tabs
- **Data:** DataTable (sorting, pagination, row click), Badge, Stat, FilterBar
- **Forms:** Button (4 variants, 3 sizes, loading), Input/Textarea/Select/Label, SearchInput, Toggle
- **Feedback:** EmptyState, LoadingState/Skeleton, Tooltip
- **Other:** ReleaseNotesViewer, VersionBadge
- **Dependencies:** `lucide-react`, `framer-motion` (1 component only), `react-dom` (createPortal)

**Theme/Tokens** — `packages/theme/src/` (~240 lines)
- `index.ts`: Color tokens (dark/light), typography (Inter + JetBrains Mono), spacing, radius, motion
- `globals.css`: CSS variables, glass-card utility, custom scrollbars, animations
- `tailwind.config.ts`: Preset extending Tailwind with the design tokens

**Types** — `packages/types/src/index.ts` (developer-relevant subset)
- `DeveloperApiKey`, `UsageRecord`, `Invoice`, `BillingPeriod`
- `AIModel`, `Capability`
- `APIResponse`, `ErrorCode`, `APIMeta`

### Copy and adapt (minor changes)

**Developer-Web Workflow App** — `apps/workflows/developer-web/` (~2,000+ lines)
This is essentially a proto-Studio. Key pieces:
- `components/tabs/APIKeysTab.tsx` — full API key management (list, create, rotate, revoke)
- `components/api-keys/CreateKeyModal.tsx` — 2-step flow (name → raw key + "store securely" warning)
- `components/api-keys/KeyDetailPanel.tsx` — side sheet with usage drill-down
- `components/tabs/UsageBillingTab.tsx` — key selector, date range, area charts
- `components/usage/UsageCharts.tsx` — 3 Recharts area charts (sessions, minutes, cost)
- `components/tabs/ModelsTab.tsx` — search, filter, cards, compare drawer
- Currently uses mock data (`data/mockData.ts`) — wire to real Gateway API

**Layout Shell** — `apps/web-next/src/components/layout/`
- `app-layout.tsx`: Sidebar + content grid with rounded card panel, collapsible sidebar
- `sidebar.tsx`: Resizable, icon+label nav, section grouping (remove plugin loading)
- `top-bar.tsx`: Page title from pathname, notification bell

**Auth Context** — `apps/web-next/src/contexts/auth-context.tsx` (~434 lines)
- Login/logout, OAuth, token in localStorage + cookie, CSRF management
- `hasRole()`, `hasPermission()` helpers
- Session validation and refresh — simplify by removing plugin/tenant layer

**API Utilities** — `apps/web-next/src/lib/`
- `api/response.ts`: Standardized `success()`, `error()`, `errors.badRequest()` etc.
- `rateLimit.ts`: In-memory LRU rate limiters (auth: 10/min, api: 100/min, etc.)
- `api/csrf.ts`: HMAC-SHA256 session-tied CSRF tokens

**Developer Service Backend** — `services/workflows/developer-svc/`
- Express.js with RESTful endpoints for models, keys, usage
- In-memory store (swap for Prisma)
- API key utilities: `packages/database/src/dev-api/key-utils.ts` (parse, hash, format: `naap_[id]_[secret]`)

### Skip (NAAP-specific)

- PluginContext, plugin-sdk, plugin loading system
- ShellContext EventBus (over-engineered for a single app)
- useDashboardQuery (GraphQL-over-EventBus)
- Ably realtime (nice-to-have later)
- Middleware plugin routing
- Network monitor types (Gateway, Orchestrator, Ticket, etc.)

---

## Epic: Build Studio

### Phase 1: Foundation (Extract & Scaffold)

#### Issue 1: Extract shared UI component package
- Copy 18 components from NAAP `packages/ui/src/` into `@livepeer/ui`
- Generalize VersionBadge (remove hardcoded version), ReleaseNotesViewer (remove hardcoded content)
- Peer deps: `react`, `lucide-react`, `framer-motion`
- Barrel export with TypeScript types

#### Issue 2: Extract shared theme/tokens package
- Copy `packages/theme/` as `@livepeer/theme`
- Tokens, globals.css, tailwind config preset

#### Issue 3: Extract shared types package
- Developer-relevant types only: `DeveloperApiKey`, `UsageRecord`, `Invoice`, `BillingPeriod`, `AIModel`, `APIResponse`, `ErrorCode`
- Drop network-monitor types

#### Issue 4: Scaffold Studio Next.js app
- Next.js 14+ with App Router
- Wire `@livepeer/ui` + `@livepeer/theme`
- Tailwind with theme preset
- Structure: `app/`, `components/`, `lib/`, `hooks/`, `contexts/`

### Phase 2: Layout & Auth

#### Issue 5: Build layout shell (sidebar + topbar + content area)
- Adapt NAAP's AppLayout/Sidebar/TopBar
- Static nav: Dashboard, Streams, API Keys, Usage, Assets, Webhooks, Settings
- Collapsible sidebar, responsive

#### Issue 6: Implement auth context and login flow
- Adapt NAAP's AuthContext (token + cookie, OAuth, CSRF)
- Login page, session validation, protected route middleware

#### Issue 7: Set up API utilities layer
- Copy response helpers, rate limiting, CSRF
- Base API client hook for Gateway API calls

### Phase 3: Core Features

#### Issue 8: Dashboard overview page
- KPI row (Stat): total streams, active streams, API usage, minutes transcoded
- Recent streams table (DataTable)
- Usage chart (UsageCharts adapted)
- Quick actions: create stream, create API key

#### Issue 9: API Keys management page
- Adapt from NAAP `developer-web/components/api-keys/`
- List (DataTable + status badges), create (2-step modal), rotate, rename, revoke, delete
- Key detail side panel with usage
- Wire to Gateway API

#### Issue 10: Streams management page
- List with search/filter (SearchInput + FilterBar + DataTable)
- Create stream modal (name, profiles, record toggle)
- Stream detail: overview, config, analytics tabs
- Status badges (active/idle/error)

#### Issue 11: Usage & Billing page
- Adapt NAAP's UsageBillingTab
- Key/stream selector, date range filter (7d/30d/billing period)
- Area charts: minutes transcoded, delivered, cost
- Invoice list

### Phase 4: Extended Features

#### Issue 12: Assets management page
- Upload flow, asset list (processing/ready/error), detail with playback URL

#### Issue 13: Webhooks management page
- List, create/edit modal (URL, events, secret), enable/disable toggle, logs

#### Issue 14: Settings page
- Profile editing, notification preferences, team management

#### Issue 15: Multistream targets UI
- Config on stream detail, target list with toggles, add target modal

### Phase 5: Polish

#### Issue 16: Real-time stream status updates
- WebSocket/SSE for live status, no polling

#### Issue 17: Onboarding flow for new users
- Empty states with guided actions, first-stream wizard

---

## Dependency Graph

```
Phase 1: [1, 2, 3] (parallel) → [4]
Phase 2: [4] → [5, 6, 7] (parallel)
Phase 3: [5, 6, 7] → [8, 9, 10, 11] (parallel)
Phase 4: [8-11] → [12, 13, 14, 15] (parallel)
Phase 5: [12-15] → [16, 17]
```

## Key File Paths in NAAP (for extraction)

```
packages/ui/src/                              # All 18 UI components
packages/theme/src/                           # Design tokens + CSS
packages/types/src/index.ts                   # Type definitions
packages/utils/src/index.ts                   # Shared utilities
packages/database/src/dev-api/key-utils.ts    # API key utilities

apps/workflows/developer-web/src/             # Proto-Studio reference app
  pages/DeveloperView.tsx                     # Main tab interface
  components/tabs/APIKeysTab.tsx              # API key management
  components/api-keys/CreateKeyModal.tsx       # Key creation flow
  components/api-keys/KeyDetailPanel.tsx       # Key detail side panel
  components/tabs/UsageBillingTab.tsx          # Usage & billing
  components/usage/UsageCharts.tsx             # Recharts area charts
  components/tabs/ModelsTab.tsx                # Model catalog

apps/web-next/src/components/layout/          # Layout shell
  app-layout.tsx                              # Main layout grid
  sidebar.tsx                                 # Collapsible sidebar
  top-bar.tsx                                 # Top bar

apps/web-next/src/contexts/auth-context.tsx   # Auth context
apps/web-next/src/lib/api/response.ts         # API response helpers
apps/web-next/src/lib/rateLimit.ts            # Rate limiting
apps/web-next/src/lib/api/csrf.ts             # CSRF tokens

services/workflows/developer-svc/src/         # Backend reference
  server.ts                                   # Express API
  store/inMemory.ts                           # Mock data store
```
