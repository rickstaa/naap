# Livepeer Studio — Build Plan

## Context

Livepeer needs a Replicate-style developer portal ("Studio") where developers can:
1. Browse a unified catalog of AI APIs (both native Livepeer network pipelines and third-party services like Daydream, Blueclaw)
2. Try any API in a playground with one Studio API key
3. Get one account, one key, one bill — regardless of which API they use

The existing pieces:
- **livepeer/website** — Marketing site (Next.js 15, standalone repo, keep as-is)
- **livepeer/explorer** — Network explorer (keep separate, link via Vercel rewrites)
- **rickstaa/naap** — Network monitor with reusable UI components, auth patterns, gateway proxy, and a developer-web workflow app that's essentially a Studio prototype

Studio will be a **new standalone repo** that reuses extracted code from NAAP. The Go Gateway handles network jobs for now. Solution providers integrate via HMAC-signed proxy (no OAuth required from providers).

---

## Architecture

```
livepeer.org (website repo, Vercel rewrites)
  /           → website app
  /explorer   → explorer app (separate repo)
  /studio     → Studio app (new repo)

Studio repo:
  apps/
    studio/                  # Next.js 15 App Router
  packages/
    ui/                      # 18 components from NAAP
    theme/                   # Design tokens from NAAP
```

### Backend strategy
```
Network APIs:      Studio API key → Go Gateway HTTP API → Livepeer Network
Third-party APIs:  Studio API key → HMAC proxy → Provider's API
                   (or OAuth token if provider supports it)
```

No key vault. No stored third-party API keys. Studio is the auth + billing layer.
Both types exposed through one unified proxy: `POST /api/v1/run/:api/:path`

---

## What to Extract from NAAP

### UI Components (copy as-is)
Source: `/home/user/naap/packages/ui/src/`
Files: Badge, Button, Card, ConfirmDialog, DataTable, EmptyState, FilterBar, Input, LoadingState, Modal, ReleaseNotesViewer, SearchInput, Stat, Tabs, Toggle, Tooltip, VersionBadge, index.ts
Dependencies: react, lucide-react, framer-motion (1 component only)
Changes needed: Remove VersionBadge's hardcoded LATEST_LIVEPEER_VERSION, generalize ReleaseNotesViewer content

### Theme (copy as-is)
Source: `/home/user/naap/packages/theme/src/`
Files: index.ts (tokens), globals.css (CSS vars + utilities), tailwind.config.ts

### Developer-Web Reference App (copy and adapt)
Source: `/home/user/naap/apps/workflows/developer-web/src/components/`
Files to copy:
- `tabs/APIKeysTab.tsx` → API key management page
- `api-keys/CreateKeyModal.tsx` → 2-step key creation flow
- `api-keys/ApiKeyTable.tsx` → key list table
- `api-keys/KeyDetailPanel.tsx` → side panel with usage
- `tabs/UsageBillingTab.tsx` → usage page
- `usage/UsageCharts.tsx` → Recharts area charts
- `tabs/ModelsTab.tsx` → pipeline/model browsing (rename to Capabilities)
- `ModelCard.tsx`, `ModelDetailPanel.tsx`, `CompareDrawer.tsx`
Changes: Strip mock data imports, wire to real API calls

### Auth Patterns (adapt)
Source: `/home/user/naap/apps/web-next/src/contexts/auth-context.tsx`
Take: Login/logout flow, token in localStorage + cookie, session validation, CSRF
Strip: Plugin/tenant system, team context, wallet login

### API Utilities (copy as-is)
Source: `/home/user/naap/apps/web-next/src/lib/`
- `api/response.ts` — standardized success/error responses
- `rateLimit.ts` — in-memory rate limiters
- `api/csrf.ts` — HMAC-SHA256 CSRF tokens

### Layout Shell (adapt)
Source: `/home/user/naap/apps/web-next/src/components/layout/`
- `app-layout.tsx` — sidebar + content grid
- `sidebar.tsx` — collapsible nav (strip plugin loading)
- `top-bar.tsx` — page title + notifications

---

## Execution Plan — Day by Day

### Day 1: Scaffold + UI extraction

**Commit 1: Init Next.js 15 app**
```bash
npx create-next-app@latest studio --app --tailwind --typescript --eslint
```
- Delete boilerplate (default page content, icons)
- Verify: `pnpm dev` works, blank page renders

**Commit 2: Add design tokens and globals.css**
- Copy `packages/theme/src/index.ts` → `packages/theme/src/index.ts`
- Copy `packages/theme/src/globals.css` → `packages/theme/src/globals.css`
- Copy `packages/theme/src/tailwind.config.ts` → `packages/theme/src/tailwind.config.ts`
- Wire `apps/studio/tailwind.config.ts` to use theme preset
- Verify: dark background, Inter + JetBrains Mono fonts load

**Commit 3: Add UI component library**
- Copy all 18 files from NAAP `packages/ui/src/` → `packages/ui/src/`
- Fix imports: `@naap/ui` → relative paths or `@livepeer/ui` workspace alias
- Remove hardcoded version from VersionBadge
- Add test page at `/test` rendering: Button, Card, Badge, DataTable, Modal, Input
- Verify: all components render without errors
- Delete test page after verification

**Commit 4: Add layout shell**
- Create `components/layout/app-layout.tsx` — adapted from NAAP
- Create `components/layout/sidebar.tsx` — static nav items:
  - Dashboard, Explore APIs, API Keys, Usage, Settings
- Create `components/layout/top-bar.tsx`
- Wire into `app/(dashboard)/layout.tsx`
- Verify: layout renders, sidebar collapses, nav items visible

---

### Day 2: Auth + API layer

**Commit 5: Add auth context**
- Create `contexts/auth-context.tsx` — adapted from NAAP's auth-context
- Provide: user, isAuthenticated, isLoading, login(), logout()
- Token stored in localStorage + cookie (for middleware)
- Mock auth for now (hardcoded token accepted)
- Verify: login sets state, logout clears it

**Commit 6: Add login page + protected routes**
- Create `app/login/page.tsx` — email + password form (Input, Button components)
- Create `middleware.ts` — redirect unauthenticated users to /login
- Verify: can't reach /dashboard without logging in, login redirects to dashboard

**Commit 7: Add API utilities**
- Copy `lib/api/response.ts` from NAAP (success/error helpers)
- Copy `lib/rateLimit.ts` from NAAP
- Create `lib/api/gateway.ts` — thin wrapper for Go Gateway calls:
  ```ts
  export async function gatewayFetch(path: string, options?: RequestInit) {
    return fetch(`${GATEWAY_URL}${path}`, {
      ...options,
      headers: { Authorization: `Bearer ${apiKey}`, ...options?.headers }
    })
  }
  ```
- Verify: utility functions importable, types correct

---

### Day 3: API catalog (the Replicate homepage)

**Commit 8: Add unified API browse page**
- Create `app/(dashboard)/explore/page.tsx`
- Copy and adapt NAAP's `ModelsTab.tsx` → card grid layout
- Copy `ModelCard.tsx` → `components/explore/api-card.tsx`
- Use-case tabs: All, Video, Image, Text, Audio
- SearchInput + FilterBar for filtering by category, cost, latency
- Provider badge on each card: "LIVEPEER" (network) or "by ProviderName" (third-party)
- Featured section at top for curated APIs
- Fetch from `/api/v1/apis` which returns both network + third-party APIs
- Verify: page loads, cards render, tabs and search work

**Commit 9: Add API detail + auto-generated playground**
- Create `app/(dashboard)/explore/[slug]/page.tsx`
- Copy and adapt `ModelDetailPanel.tsx` → full page with:
  - Name, provider, pricing, latency, description
  - Auto-generated playground form from endpoint params schema (string→input, enum→dropdown, number→slider, file→upload)
  - Response renderer (detects image/video/text/JSON)
  - Quick start code snippets (curl + Python SDK)
- Network APIs: playground calls Go Gateway via Studio API route
- Third-party APIs: playground calls HMAC proxy (or shows "Connect" for OAuth providers)
- Verify: click card → detail page → run API → see output

---

### Day 4: API Keys

**Commit 10: Add API Keys list page**
- Create `app/(dashboard)/keys/page.tsx`
- Copy NAAP's `ApiKeyTable.tsx` → `components/keys/key-table.tsx`
- DataTable with columns: name, key prefix, status (Badge), created, last used
- Empty state when no keys
- Verify: page loads, shows keys or empty state

**Commit 11: Add create API key flow**
- Copy NAAP's `CreateKeyModal.tsx` → `components/keys/create-key-modal.tsx`
- 2-step flow: enter name → show raw key with copy button + "store securely" warning
- POST to create key endpoint, key appears in table after creation
- Verify: create key, see it in list, copy works

**Commit 12: Add key actions (revoke, rename, rotate)**
- Copy NAAP's `KeyDetailPanel.tsx` → `components/keys/key-detail-panel.tsx`
- Action buttons on table rows: rename, rotate, revoke
- ConfirmDialog for revoke
- Side panel on row click showing key detail + usage
- Verify: each action works, table updates

---

### Day 5: Dashboard + Usage

**Commit 13: Add Dashboard overview**
- Create `app/(dashboard)/dashboard/page.tsx`
- Stat cards row: total API calls, active keys, available capabilities, credits remaining
- Recent activity table (DataTable): last 10 API calls with status, latency, capability used
- Quick action buttons: "Create API Key", "Browse Capabilities"
- Verify: stats render (even if zero), table shows data

**Commit 14: Add Usage page**
- Create `app/(dashboard)/usage/page.tsx`
- Copy NAAP's `UsageBillingTab.tsx` → adapt for Studio
- Copy `UsageCharts.tsx` → `components/usage/usage-charts.tsx`
- Date range selector (7d, 30d, 90d)
- Per-key breakdown dropdown
- Area charts: API calls, compute minutes, cost
- Verify: charts render, date range filter works

---

### Day 6: Third-party API proxy + provider registration

**Commit 15: Add HMAC proxy for third-party APIs**
- Create `app/api/v1/proxy/[api]/[...path]/route.ts`
- Verify Clerk session → load API record → sign with shared_secret → forward
- Headers: X-Studio-Signature, X-Studio-Timestamp, X-Studio-User-Id
- Rate limit per user
- Verify: request proxied, HMAC valid, provider receives signed request

**Commit 16: Add provider registration page**
- Create `app/(dashboard)/providers/register/page.tsx`
- Step 1: Name, API base URL, description
- Step 2: Define endpoints (or upload OpenAPI spec)
- Step 3: Integration verification (Studio sends test HMAC request)
- Step 4: Configure listing (logo, category, tags, pricing)
- Returns shared_secret for the provider
- Verify: full registration flow works, test request succeeds

**Commit 17: Wire third-party APIs into the catalog**
- Third-party APIs appear alongside network APIs in `/explore`
- Same card component, "by ProviderName" badge
- Detail page playground calls HMAC proxy instead of gateway
- "Use via Studio" (one-click, HMAC) vs "Connect" (OAuth, if supported)
- Verify: browse page shows mixed results, playground works for both types

---

### Day 7: Polish + Deploy

**Commit 18: Add Settings page**
- Create `app/(dashboard)/settings/page.tsx`
- Profile section (name, email)
- Connected Solutions section (list of authorized solutions)
- Verify: settings load, profile editable

**Commit 19: Wire auth to real backend**
- Replace mock auth with actual auth endpoint
- Test full flow: signup → login → create key → browse capabilities → try pipeline → see usage
- Verify: end-to-end flow works

**Commit 20: Deploy**
- Configure Vercel project
- Set environment variables (GATEWAY_URL, auth secrets)
- Add rewrite to livepeer/website: `/studio/:path*` → Studio app
- Verify: studio.livepeer.org works, livepeer.org/studio proxies correctly

---

## Solution Provider Integration (Week 2)

### Provider registration
```
POST /api/v1/admin/solutions
{
  name: "Ghibli Video",
  slug: "ghibli-video",
  upstream_url: "https://ghibli-api.dev",
  description: "...",
  pricing: { per_minute: 0.05 }
}
→ Returns { shared_secret: "sk_..." }
```

### Provider verification (their side, ~10 lines)
```python
import hmac, hashlib

def verify_studio_request(request, shared_secret):
    signature = request.headers["X-Studio-Signature"]
    expected = hmac.new(shared_secret, request.body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(signature, expected)
```

### Billing (Week 3-4)
- Stripe Checkout for credits
- Usage metering per API call
- Stripe Connect for provider payouts (Month 2)

---

## Verification Checklist

After each day, the app must:
- [ ] `pnpm dev` starts without errors
- [ ] All pages render without console errors
- [ ] Navigation between pages works
- [ ] Auth flow works (login required for dashboard pages)
- [ ] No NAAP-specific imports remain (no `@naap/*`)

End-to-end test (Day 7):
- [ ] New user signs up via Clerk
- [ ] Creates a Studio API key
- [ ] Browses "Explore APIs" — sees both network and third-party APIs in one catalog
- [ ] Clicks a network API (e.g., text-to-image), runs it in playground, sees result
- [ ] Clicks a third-party API (e.g., Daydream), clicks "Use via Studio", runs it
- [ ] Checks usage page, sees both API calls logged
- [ ] Provider registers a new API via /providers/register, it appears in catalog

---

## Key Decisions Made

1. **Separate repo, not in NAAP** — Studio is a different product with different users and release cadence
2. **Go Gateway for now** — Already running, HTTP API. Swap to Python SDK or JS SDK later if needed
3. **Two-phase auth for Solutions** — HMAC proxy to bootstrap (week 1-2), OAuth Connect long-term
4. **No key vault** — No raw API keys stored. OAuth tokens (revocable, scoped) stored encrypted when providers support OAuth. HMAC signing when they don't.
5. **No monorepo with website** — Connect via Vercel rewrites. Each app deploys independently
6. **Copy from NAAP, don't abstract** — No shared npm packages to publish. Copy the 18 UI components and theme into Studio's repo. Extract into packages later when a second consumer exists

---

## Marketplace Taxonomy & Developer UX

### The Problem

Studio has two types of offerings:
1. **Raw network pipelines** — text-to-image, LV2V, etc. directly on Livepeer orchestrators via gateway
2. **Third-party services** — Daydream (managed real-time AI video), Blueclaw (OpenAI-compatible inference), livepeer/pipelines (API for AI pipelines)

The difference is infrastructure: raw pipelines go straight to orchestrators, third-party services run their own routing/fallback/SLA layer on top. But **developers don't care about this distinction**. They care about: "what can I build, how do I call it, what does it cost."

### The Solution: One catalog, not two

**Don't split "Capabilities" vs "Solutions."** Call everything an **"API"** and organize by use case, not infrastructure.

Replicate calls everything a "model." We call everything an "API" because some offerings aren't models — they're services (managed streaming, inference platforms).

### Browse page layout

```
┌─────────────────────────────────────────────────────────────┐
│  Explore APIs                                    🔍 Search   │
│                                                              │
│  [All] [Video] [Image] [Text] [Audio]     ← use-case tabs  │
│                                                              │
│  ── Featured ──────────────────────────────────────────────  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐               │
│  │ 🎬 LV2V    │ │ ☁ Daydream │ │ 🤖 Blueclaw│               │
│  │            │ │            │ │            │               │
│  │ Real-time  │ │ Managed AI │ │ OpenAI-    │               │
│  │ video AI   │ │ video      │ │ compat LLM │               │
│  │            │ │            │ │            │               │
│  │ LIVEPEER   │ │ by Daydream│ │ by Blueclaw│               │
│  │ $0.02/min  │ │ $0.05/min  │ │ Free beta  │               │
│  │ ⚡ 200ms   │ │ ⚡ 150ms   │ │ ⚡ 80ms    │               │
│  └────────────┘ └────────────┘ └────────────┘               │
│                                                              │
│  ── All APIs ──────────────────────────────────────────────  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐               │
│  │ Text to    │ │ Image to   │ │ Upscale    │               │
│  │ Image      │ │ Video      │ │            │               │
│  │ LIVEPEER   │ │ LIVEPEER   │ │ by SomeDevl│               │
│  └────────────┘ └────────────┘ └────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

### Card component — same for all, subtle provider distinction

Every API card shows the same fields:
- **Name** (what it does)
- **Provider badge**: `LIVEPEER` (network) or `by Daydream` (third-party)
- **Pricing**: per-minute, per-request, subscription, or free
- **Latency**: P50 response time
- **Use case tags**: video, image, text, audio

The provider badge is the ONLY distinction. No "capability" vs "solution" language anywhere in the UI. It's just "who runs it."

This is exactly how Replicate does it: "Official" badge for their maintained models, creator attribution for community models. Same card, same browse experience.

### Detail page — adapts to provider type

When you click an API card, the detail page adapts based on whether it's a network API or third-party:

**Network API (e.g., text-to-image):**
```
┌──────────────────────────────────────────────────┐
│  Text to Image                      LIVEPEER     │
│  Generate images from text prompts                │
│                                                    │
│  Pricing: $0.005/request                          │
│  Latency: ~2s                                     │
│  Orchestrators: 47 available                      │
│                                                    │
│  ┌─ Playground ──────────────────────────────┐    │
│  │ Prompt: [________________________]        │    │
│  │ Model: [stable-diffusion-xl ▾]            │    │
│  │ Size: [1024x1024 ▾]                       │    │
│  │                        [Run with API key] │    │
│  └───────────────────────────────────────────┘    │
│                                                    │
│  ┌─ Quick start ─────────────────────────────┐    │
│  │ curl -X POST studio.livepeer.org/v1/run \ │    │
│  │   -H "Authorization: Bearer YOUR_KEY" \   │    │
│  │   -d '{"prompt": "..."}'                  │    │
│  └───────────────────────────────────────────┘    │
│                                                    │
│  All requests go through your Studio API key.      │
│  [Create API key →]                                │
└──────────────────────────────────────────────────┘
```

**Third-party API (e.g., Daydream):**
```
┌──────────────────────────────────────────────────┐
│  Daydream Real-Time Video          by Daydream   │
│  Real-time AI video transformation via WebRTC     │
│                                                    │
│  Pricing: $0.05/min                               │
│  Latency: ~150ms (real-time)                      │
│  SLA: 99.9% uptime                                │
│                                                    │
│  ┌─ Playground ──────────────────────────────┐    │
│  │ Model: [SD Turbo ▾]                       │    │
│  │ Prompt: [________________________]        │    │
│  │ Preset: [Anime] [Dream] [Neon] [Comic]   │    │
│  │                            [Run — Connect]│    │
│  └───────────────────────────────────────────┘    │
│                                                    │
│  ┌─ Quick start ─────────────────────────────┐    │
│  │ # Using Daydream's API directly           │    │
│  │ curl -X POST api.daydream.live/streams \  │    │
│  │   -H "Authorization: Bearer YOUR_KEY" \   │    │
│  │   -d '{"model": "sd-turbo"}'              │    │
│  │                                            │    │
│  │ # Or through Studio (unified billing)     │    │
│  │ curl -X POST studio.livepeer.org/v1/run \ │    │
│  │   -H "Authorization: Bearer STUDIO_KEY" \ │    │
│  │   -d '{"api": "daydream", ...}'           │    │
│  └───────────────────────────────────────────┘    │
│                                                    │
│  ⓘ This API is provided by Daydream.              │
│  [Connect Daydream account] or [Use via Studio]    │
└──────────────────────────────────────────────────┘
```

### Two paths to use a third-party API

**Path A: "Use via Studio" (HMAC proxy, no provider account needed)**
- User clicks "Run" in playground
- Studio proxies request with HMAC signature
- Provider trusts Studio, serves request
- Studio bills the user
- Developer never creates a provider account

**Path B: "Connect" (OAuth, for power users)**
- User clicks "Connect Daydream account"
- OAuth flow → user authorizes Studio to call Daydream on their behalf
- User may get better rates, more features, or SLA guarantees
- Studio stores OAuth token, proxies with it

Most users will use Path A. It's the "Replicate experience" — one account, one key, everything works. Path B is for developers who already have provider accounts or want direct relationships.

### Provider onboarding flow (how a Solution gets listed)

```
Provider visits studio.livepeer.org/providers

Step 1: Register
  - Company/project name
  - API base URL
  - Description + docs link
  → Studio generates shared_secret for HMAC

Step 2: Define endpoints
  - Add endpoints (method, path, description, pricing)
  - Or upload OpenAPI spec → auto-populate
  - Set pricing per endpoint (per-request, per-minute, subscription)

Step 3: Verify integration
  - Add HMAC verification to their API (~10 lines, we provide snippets)
  - Studio sends test request → verify HMAC is accepted
  - ✅ "Integration verified"

Step 4: Configure listing
  - Add logo, screenshots, use case tags
  - Write description
  - Choose category (video, image, text, audio)
  - Submit for review

Step 5: Review & publish
  - Studio team reviews (manual for now)
  - Published → appears in catalog
```

**NO plugin required.** No Daydream-style custom UI plugin. The provider doesn't build a playground — Studio generates one from their OpenAPI spec or endpoint definitions. This is the key simplification: providers define endpoints, Studio renders the playground automatically.

### Provider playground generation (auto from endpoints)

When a provider registers endpoints:
```json
{
  "method": "POST",
  "path": "/generate",
  "params": [
    { "name": "prompt", "type": "string", "required": true },
    { "name": "model", "type": "enum", "values": ["sd-turbo", "sdxl"], "default": "sd-turbo" },
    { "name": "num_frames", "type": "number", "min": 1, "max": 120, "default": 30 }
  ],
  "response_type": "video"
}
```

Studio auto-generates a playground form:
- String params → text input
- Enum params → dropdown
- Number params → slider or number input
- File params → upload
- Response type → appropriate renderer (image, video, text, JSON)

Provider doesn't write any frontend code. This is how Replicate's playground works — auto-generated from the model's input schema.

### Naming decision

| Term | Where it appears | Why |
|------|-----------------|-----|
| **API** | Everywhere user-facing ("Explore APIs", "API detail page") | Generic, clear, no infrastructure leak |
| **Provider** | Card attribution ("by Daydream") | Clear who runs it |
| **LIVEPEER** badge | Cards for network APIs | Shows it's native to the network |
| **Connect** | Button for OAuth providers | Familiar from GitHub/Slack integrations |

**Terms we DON'T use in the UI:**
- ~~Capability~~ (too technical)
- ~~Solution~~ (too enterprise)
- ~~Pipeline~~ (implementation detail)
- ~~Orchestrator~~ (infrastructure detail)
- ~~Model~~ (not everything is a model — Daydream is a service)

### DB schema update (unified `apis` table replaces `solutions`)

```sql
CREATE TABLE apis (
  id              UUID PRIMARY KEY,
  name            TEXT NOT NULL,
  slug            TEXT UNIQUE NOT NULL,
  description     TEXT,
  provider_type   TEXT NOT NULL,           -- 'network' | 'third_party'
  provider_name   TEXT NOT NULL,           -- 'Livepeer' | 'Daydream' | 'Blueclaw'
  provider_url    TEXT,                    -- null for network APIs
  upstream_url    TEXT,                    -- null for network (uses gateway), URL for third-party
  shared_secret   TEXT,                    -- null for network, generated for third-party (HMAC)
  auth_type       TEXT DEFAULT 'studio',   -- 'studio' (network) | 'hmac' | 'oauth'
  oauth_config    JSONB,
  category        TEXT NOT NULL,           -- 'video' | 'image' | 'text' | 'audio'
  tags            TEXT[],                  -- ['real-time', 'generative', 'streaming']
  pricing_model   JSONB,                  -- { type: 'per_minute'|'per_request'|'subscription', amount: 0.05 }
  latency_p50_ms  INT,
  featured        BOOLEAN DEFAULT FALSE,
  status          TEXT DEFAULT 'draft',
  owner_user_id   TEXT,                    -- null for network APIs (owned by Livepeer)
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE api_endpoints (
  id              UUID PRIMARY KEY,
  api_id          UUID REFERENCES apis(id),
  method          TEXT NOT NULL,
  path            TEXT NOT NULL,
  description     TEXT,
  params          JSONB,                   -- input schema for playground generation
  response_type   TEXT,                    -- 'image' | 'video' | 'text' | 'json' | 'stream'
  pricing         JSONB,                   -- per-endpoint pricing override
  rate_limit      INT                      -- requests per minute
);
```

Network APIs are pre-seeded rows with `provider_type = 'network'`. Third-party APIs are registered by providers.

---

## Technical Details

### A. Auth Architecture

Studio has TWO auth layers:

**Layer 1: Marketplace login (who is this user?)**
- Use **Clerk** as the identity provider
- Login methods: Google, GitHub, email magic link (configurable in Clerk dashboard)
- Clerk issues a JWT per session, Studio stores it as the session token
- This is Studio's own auth — has nothing to do with providers

**Layer 2: Provider connections (can we call this provider's API as this user?)**
- Per-provider auth mechanism (OAuth or HMAC, see below)
- This is how Studio calls Solution provider APIs on behalf of the user

```
┌─────────────────────────────────────────────────────────────┐
│ USER                                                         │
│   │                                                          │
│   ├── Login to Studio (Clerk) ──── Layer 1: "Who are you?"  │
│   │                                                          │
│   ├── Connect to Pipelines ─────── Layer 2: OAuth token      │
│   ├── Connect to SolutionB ─────── Layer 2: OAuth token      │
│   └── Use Capabilities ────────── Layer 2: Studio API key    │
│                                    (no provider connection    │
│                                     needed, Studio IS the     │
│                                     provider for network      │
│                                     capabilities)             │
└─────────────────────────────────────────────────────────────┘
```

### B. Capabilities Auth (Livepeer Network)

Studio IS the auth layer for network capabilities. No third-party auth needed.

```
User → Studio API key → Studio backend → Go Gateway → Orchestrators
```

- User creates a Studio API key in the dashboard
- Studio backend validates the key (SHA-256 hash lookup)
- Studio backend calls Go Gateway with its own service credential
- Usage metered per user in Studio's DB

**Key format:** `lp_studio_[32-hex]`
**Storage:** SHA-256 hash in DB, raw key shown once at creation

### C. Solutions Auth — Phase 1: HMAC Proxy (Week 2, ships fast)

For Solution providers who don't have OAuth yet (most indie developers).

**Provider onboarding:**
```
1. Provider registers on Studio → gets shared_secret
2. Provider adds HMAC verification to their API (~10 lines)
3. Done — their API is now on the marketplace
```

**Request flow:**
```
User (logged into Studio via Clerk)
  → POST /api/v1/proxy/ghibli-video/generate { body }
  → Studio backend:
      1. Verify user's Clerk session
      2. Look up provider's shared_secret from DB
      3. Compute: signature = HMAC-SHA256(shared_secret, timestamp + body)
      4. Forward to provider:
           POST https://ghibli-api.dev/generate
           X-Studio-Signature: <signature>
           X-Studio-Timestamp: <timestamp>
           X-Studio-User-Id: <clerk_user_id>
           X-Studio-Plan: <user_plan>
           Body: <original body>
      5. Provider verifies HMAC, serves request
      6. Studio logs usage for billing
```

**Provider verification (their side):**
```python
import hmac, hashlib, time

def verify_studio_request(request, shared_secret):
    signature = request.headers["X-Studio-Signature"]
    timestamp = request.headers["X-Studio-Timestamp"]

    # Reject if older than 5 minutes (replay protection)
    if abs(time.time() - int(timestamp)) > 300:
        return False

    payload = f"{timestamp}.{request.body}".encode()
    expected = hmac.new(
        shared_secret.encode(), payload, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(signature, expected)
```

**DB schema (solutions table):**
```sql
CREATE TABLE solutions (
  id              UUID PRIMARY KEY,
  name            TEXT NOT NULL,
  slug            TEXT UNIQUE NOT NULL,
  upstream_url    TEXT NOT NULL,
  shared_secret   TEXT NOT NULL,        -- generated by Studio
  description     TEXT,
  pricing_model   JSONB,                -- { per_request, per_minute, etc. }
  auth_type       TEXT DEFAULT 'hmac',  -- 'hmac' | 'oauth'
  oauth_config    JSONB,                -- null for HMAC providers
  owner_user_id   TEXT NOT NULL,        -- Clerk user ID of provider
  status          TEXT DEFAULT 'draft', -- draft | published | suspended
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### D. Solutions Auth — Phase 2: OAuth Connect (Week 3-4, for providers who support it)

For providers like `livepeer/pipelines` that already have auth (Clerk/API keys) and can add OAuth.

**What providers must implement:**
```
Required:
  POST /oauth/authorize  — authorization endpoint
  POST /oauth/token      — token exchange endpoint

Optional:
  POST /oauth/revoke     — token revocation
  GET  /oauth/userinfo   — user info endpoint
```

**What Studio implements (provider-agnostic OAuth Connect service):**

```
Studio endpoints:
  GET  /connect/:providerId/start    — generate state + PKCE, redirect to provider
  GET  /connect/:providerId/callback — exchange code for tokens, store encrypted
  POST /connect/:providerId/disconnect — revoke + delete tokens
```

**DB schema (provider_connections table):**
```sql
CREATE TABLE provider_connections (
  id                    UUID PRIMARY KEY,
  marketplace_user_id   TEXT NOT NULL,       -- Clerk user ID
  provider_id           UUID REFERENCES solutions(id),
  provider_user_id      TEXT,                -- user ID from provider's system
  access_token_enc      TEXT NOT NULL,       -- AES-256-GCM encrypted
  refresh_token_enc     TEXT,                -- AES-256-GCM encrypted
  token_expires_at      TIMESTAMPTZ,
  scopes                TEXT[],
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  revoked_at            TIMESTAMPTZ,
  UNIQUE(marketplace_user_id, provider_id)
);
```

**OAuth Connect flow:**
```
1. User clicks "Connect Pipelines" in Studio
2. Studio redirects to:
     https://pipelines.livepeer.org/oauth/authorize?
       client_id=studio-marketplace&
       redirect_uri=https://studio.livepeer.org/connect/pipelines/callback&
       scope=run-jobs+read-usage&
       state=<csrf_state>&
       code_challenge=<pkce_challenge>&
       code_challenge_method=S256

3. User sees consent screen at Pipelines: "Allow Livepeer Studio to run jobs?"
4. User approves → Pipelines redirects to callback with code
5. Studio backend exchanges code for tokens:
     POST https://pipelines.livepeer.org/oauth/token
       grant_type=authorization_code&
       code=<code>&
       code_verifier=<pkce_verifier>&
       client_id=studio-marketplace&
       client_secret=<studio_client_secret>

6. Studio stores encrypted access_token + refresh_token
7. User can now "Try it" — Studio proxies with the OAuth token
```

**"Try it" proxy flow (OAuth):**
```
User hits "Try it" on a Pipelines model in Studio
  → Studio backend:
      1. Load provider_connection for this user + provider
      2. If token expired, refresh it
      3. Forward request:
           POST https://pipelines.livepeer.org/api/generate
           Authorization: Bearer <access_token>
      4. Return response to user
      5. Log usage
```

**Security properties of OAuth tokens vs stored API keys:**
| Property | API Keys | OAuth Tokens |
|----------|----------|-------------|
| Revocable by user | No (must ask provider) | Yes (disconnect in Studio or provider) |
| Revocable by provider | Provider must rotate all keys | Provider revokes specific token |
| Scoped | No (full access) | Yes (e.g., run-jobs only) |
| Expires | No | Yes (refresh token rotation) |
| If Studio is breached | All keys compromised forever | Tokens revocable, provider can mass-revoke |

### E. livepeer/pipelines Integration (Clerk-based shortcut)

`livepeer/pipelines` already uses Clerk for auth (`apps/api/src/plugins/auth.ts`). This gives us a faster path than full OAuth for this specific provider:

**Option 1: Shared Clerk instance (fastest, if we control pipelines)**
- Studio and Pipelines use the same Clerk project
- Studio gets a Clerk JWT for the user → forwards it to Pipelines
- Pipelines already does `verifyToken(accessToken, { secretKey: env.CLERK_SECRET_KEY })`
- No OAuth implementation needed on either side

```ts
// Studio backend — proxy to Pipelines
const token = await clerkClient.sessions.getToken(sessionId);
const resp = await fetch(`${PIPELINES_URL}${path}`, {
  headers: { Authorization: `Bearer ${token}` },
  body: req.body,
});
```

**Option 2: Pipelines adds OAuth endpoints (better long-term)**
- Studio is just another OAuth client
- Works even if Studio and Pipelines use different identity systems
- Same pattern as any other Solution provider

**Recommendation:** Start with Option 1 (shared Clerk) for Pipelines specifically. Build the generic OAuth Connect system for other providers. Migrate Pipelines to OAuth later if needed.

### F. Provider Onboarding Requirements

**To list on Studio Marketplace, a Solution must provide:**

```
Minimum (HMAC — gets you listed immediately):
  ✅ API base URL
  ✅ Endpoint documentation (OpenAPI spec preferred)
  ✅ HMAC signature verification on incoming requests
  ✅ Pricing information

Recommended (OAuth — gets you "Connect" button):
  ✅ Everything above, plus:
  ✅ OAuth 2.0 authorization endpoint
  ✅ OAuth 2.0 token endpoint
  ✅ Token revocation endpoint
  ✅ Scoped permissions (e.g., run-jobs, read-usage)
```

**Provider dashboard (what providers see in Studio):**
- Subscriber count
- Request volume / usage charts
- Revenue (when billing is live)
- API health status
- Manage shared_secret rotation

### G. Billing Architecture

**Phase 1: Free tier (Week 1)**
- Just meter usage in `usage_records` table
- No payments

**Phase 2: Stripe Checkout (Week 3-4)**
```sql
CREATE TABLE credits (
  user_id    TEXT PRIMARY KEY,       -- Clerk user ID
  balance    DECIMAL NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE usage_records (
  id              UUID PRIMARY KEY,
  user_id         TEXT NOT NULL,
  provider_id     UUID REFERENCES solutions(id),
  endpoint        TEXT NOT NULL,
  cost            DECIMAL NOT NULL,
  request_at      TIMESTAMPTZ DEFAULT NOW(),
  response_status INT
);
```

- User buys credits via Stripe Checkout
- Each API call deducts from balance
- Low balance → warning email → block at zero

**Phase 3: Stripe Connect (Month 2)**
- Providers connect their Stripe account
- Studio splits payment: Studio fee (e.g., 10%) + provider payout
- Automatic monthly payouts to providers

### H. Go Gateway vs Python SDK — Migration Path

```
Week 1-4:   Go Gateway (HTTP API, already deployed)
              Studio → fetch(GATEWAY_URL + path) → network

Month 2-3:  Evaluate Python SDK for multi-user support
              If needed: FastAPI wrapper around SDK
              Studio → fetch(PYTHON_SERVICE_URL + path) → SDK → network

Later:      JS SDK port (control plane only)
              Studio → import { startJob } from '@livepeer/sdk'
              No external service needed for basic operations
```

**When to migrate:** When you need per-user orchestrator selection, custom pricing logic, or the Go Gateway becomes a bottleneck for multi-user workloads.

### I. Complete Request Flow Diagrams

**Capability request (user runs a pipeline on the network):**
```
Browser
  → POST /api/v1/capabilities/lv2v/run (Studio API key in header)
  → Studio API route:
      1. Validate Studio API key (SHA-256 lookup)
      2. Check user credits balance
      3. POST ${GATEWAY_URL}/api/v1/pipelines/lv2v
           Authorization: Bearer ${STUDIO_SERVICE_KEY}
      4. Deduct credits from user balance
      5. Insert usage_record
      6. Return result to browser
```

**Solution request via HMAC (provider doesn't have OAuth):**
```
Browser
  → POST /api/v1/proxy/ghibli-video/generate (Clerk session cookie)
  → Studio API route:
      1. Verify Clerk session → get userId
      2. Check user credits balance
      3. Load solution record → get shared_secret, upstream_url
      4. Sign: HMAC-SHA256(shared_secret, timestamp + body)
      5. POST ${upstream_url}/generate
           X-Studio-Signature: <sig>
           X-Studio-Timestamp: <ts>
           X-Studio-User-Id: <userId>
      6. Deduct credits
      7. Insert usage_record
      8. Return result to browser
```

**Solution request via OAuth (provider has OAuth):**
```
Browser
  → POST /api/v1/proxy/pipelines/text-to-image (Clerk session cookie)
  → Studio API route:
      1. Verify Clerk session → get userId
      2. Check user credits balance
      3. Load provider_connection → get access_token (decrypt)
      4. If expired, refresh token
      5. POST ${upstream_url}/api/text-to-image
           Authorization: Bearer <access_token>
      6. Deduct credits
      7. Insert usage_record
      8. Return result to browser
```

### J. Repo Structure (Final)

```
livepeer-studio/
├── apps/studio/src/
│   ├── app/
│   │   ├── (dashboard)/
│   │   │   ├── dashboard/page.tsx
│   │   │   ├── explore/{page,[slug]/page}.tsx       # Unified API catalog
│   │   │   ├── keys/page.tsx
│   │   │   ├── usage/page.tsx
│   │   │   ├── providers/register/page.tsx          # Provider onboarding
│   │   │   ├── settings/page.tsx
│   │   │   └── layout.tsx
│   │   ├── login/page.tsx
│   │   ├── api/v1/
│   │   │   ├── apis/route.ts                        # List all APIs (network + third-party)
│   │   │   ├── run/[api]/[...path]/route.ts         # Unified proxy (gateway or HMAC)
│   │   │   ├── keys/route.ts
│   │   │   ├── usage/route.ts
│   │   │   ├── admin/apis/route.ts                  # Provider registration
│   │   │   └── connect/[provider]/{start,callback}/route.ts
│   │   └── middleware.ts
│   ├── components/
│   │   ├── layout/{app-layout,sidebar,top-bar}.tsx
│   │   ├── explore/{api-card,api-detail,playground-form}.tsx
│   │   ├── providers/{register-form,connect-button}.tsx
│   │   ├── keys/{key-table,create-key-modal,key-detail-panel}.tsx
│   │   └── usage/usage-charts.tsx
│   ├── contexts/auth-context.tsx
│   └── lib/
│       ├── api/{response,gateway,csrf}.ts
│       ├── auth/{hmac,oauth}.ts
│       ├── encryption.ts
│       └── rateLimit.ts
├── packages/
│   ├── ui/src/{Badge,Button,Card,...,Tooltip,index}.tsx
│   └── theme/src/{index.ts,globals.css,tailwind.config.ts}
├── turbo.json
├── pnpm-workspace.yaml
└── package.json
```

---

## Appendices — Discussion Context & Decisions

### Appendix 1: Why Studio is NOT in NAAP

NAAP is a network monitor with a plugin system (EventBus, tenant isolation, dynamic connector registration, Ably realtime). Studio is a developer portal. Different product, different audience, different release cadence. NAAP's plugin architecture adds complexity Studio doesn't need.

What we take from NAAP: UI components (18, ~1,700 lines), theme tokens (~240 lines), developer-web workflow app (~2,000 lines as reference), auth patterns, API utilities. What we skip: plugin system, ShellContext EventBus, useDashboardQuery (GraphQL-over-EventBus), Ably realtime, middleware plugin routing.

### Appendix 2: Why Studio is NOT in livepeer/website monorepo

livepeer/website is a standalone Next.js 15 marketing site (React 19, Tailwind v4, Framer Motion). It's not a monorepo. Converting it into one adds complexity. Studio has different dependencies (Clerk, Recharts, database). Connect them via Vercel rewrites — one domain, independent deployments.

### Appendix 3: Two types of things on the marketplace (unified as "APIs")

Internally there are two types, but the UI presents them identically:

**Network APIs** = raw pipelines on Livepeer orchestrators. Studio is the auth layer. Studio API key → Gateway → orchestrators. Badged as "LIVEPEER" in the catalog.

**Third-party APIs** = services built on Livepeer (Daydream, Blueclaw, etc.). They run their own infra, route to Livepeer + cloud, offer SLAs. Studio proxies via HMAC or OAuth. Badged as "by ProviderName."

Both appear in one "Explore APIs" catalog, organized by use case (Video, Image, Text, Audio). No "Capabilities" or "Solutions" language in the UI. Developers browse by what they want to build, not by infrastructure type. See "Marketplace Taxonomy & Developer UX" section for full design.

### Appendix 4: NAAP's service gateway — what it does

NAAP has a full API gateway that abstracts multiple upstream APIs behind a single NAAP API key. The flow:
1. Admin registers a "connector" (upstream API definition with endpoints, auth type, secret refs)
2. Admin stores upstream API credentials in SecretVault (AES-256-GCM encrypted)
3. Admin creates rate limit plans and issues API keys to users
4. User makes request with NAAP key → gateway authorizes → resolves connector → decrypts upstream secret → injects into request → proxies to upstream → logs usage

This is powerful but over-engineered for Studio v1. Studio uses a simpler model: HMAC signing for Solutions (no secret vault), direct Gateway calls for Capabilities.

Key NAAP files for reference:
- Proxy pipeline: `apps/web-next/src/app/api/v1/gw/[connector]/[...path]/route.ts` (372 lines, 13-step pipeline)
- Secret encryption: `apps/web-next/src/lib/gateway/encryption.ts` (AES-256-GCM)
- Connector definitions: `plugins/service-gateway/connectors/*.json` (26 connectors incl. Stripe, OpenAI, Replicate)
- Seed script showing full setup: `bin/seed-leaderboard-gateway.ts`

### Appendix 5: Security — why we don't store API keys

If Studio stored raw API keys for 50 providers × 10,000 users = 500,000 keys in one DB. One breach = every user's access to every provider compromised. NAAP does this with AES-256-GCM encryption, but the server-side `ENCRYPTION_KEY` env var is a single point of compromise.

Studio's approach instead:
- **Capabilities:** No third-party keys. Studio IS the auth layer.
- **Solutions (HMAC phase):** No user keys stored at all. Studio signs requests with provider's shared_secret. Provider verifies HMAC.
- **Solutions (OAuth phase):** OAuth tokens stored encrypted. These are revocable, scoped, expiring. If breached, providers mass-revoke. Users disconnect individual providers.

### Appendix 6: livepeer/pipelines auth (existing)

`livepeer/pipelines` uses Fastify with Clerk JWT + API key auth (`apps/api/src/plugins/auth.ts`):
1. Extract Bearer token from Authorization header
2. Try Clerk JWT verification (`@clerk/backend verifyToken`) → sets `request.userId = sub`
3. Fallback: SHA-256 hash token → look up in API keys table → sets `request.userId`
4. Credit/usage tracked by `request.userId`

For Studio integration: use shared Clerk instance. Studio logs user in via Clerk, forwards Clerk JWT to Pipelines. Pipelines already verifies it. No changes needed on Pipelines side (just ensure `CLERK_SECRET_KEY` is from the same Clerk project).

Long-term: Pipelines adds OAuth endpoints so Studio can do standard OAuth Connect (same as any other Solution provider).

### Appendix 7: Go Gateway vs Python SDK vs JS SDK

**Go Gateway** (go-livepeer) = deployed binary with HTTP endpoints. Already running. Studio calls it via `fetch()`. Single process, single wallet. Use for now.

**Python SDK** (j0sh/livepeer-python-gateway) = Python library for direct orchestrator communication via protobuf/trickle. Not a web server — needs FastAPI wrapper to expose HTTP. Gives full control over orchestrator selection, per-user pricing. Better for multi-user at scale. But adds a Python service to deploy.

**JS SDK** (doesn't exist yet) = would be a partial port of the Python SDK's control plane (orchestrator selection, job lifecycle). ~1,000 lines. Could run in Next.js API routes. But media encode/decode is hard in JS — only control plane is portable.

Migration path: Go Gateway now → evaluate Python SDK at scale → JS SDK port for control plane later.

### Appendix 8: Anti-slop commit rules

When working with AI to build Studio:
1. One concern per commit ("Add API keys page" not "Add API keys, usage, and settings")
2. Each commit must build and run (`pnpm dev` works)
3. No placeholder code (no empty files, TODO components, stub functions)
4. Copy from NAAP then simplify (don't rewrite from scratch)
5. Read every line you copy (remove NAAP-specific imports, plugin refs)
6. No abstractions until the third use (inline `fetch()` before creating `useGatewayClient`)
7. Manual UI test after each commit (click every state: empty, loading, data, error)
