# Adding a Plugin to NAAP

## 1. Create your plugin

```bash
# Frontend-only (recommended starting point)
naap-plugin create my-plugin

# Full-stack without database
naap-plugin create my-plugin --template full-stack --simple

# Full-stack with PostgreSQL (requires Docker)
naap-plugin create my-plugin --template full-stack
```

## 2. Develop

```bash
cd my-plugin
naap-plugin dev
```

Edit `frontend/src/App.tsx` — your plugin is live at `http://localhost:3000`.

## 3. Key files

| File | Purpose |
|------|---------|
| `plugin.json` | Plugin manifest (name, routes, ports) |
| `frontend/src/App.tsx` | Main React component using `createPlugin()` |
| `backend/src/server.ts` | Express server (if full-stack) |
| `backend/prisma/schema.prisma` | Database schema (if using DB) |

### Minimal `plugin.json`

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "frontend": {
    "devPort": 3010,
    "routes": ["/my-plugin", "/my-plugin/*"]
  }
}
```

### Minimal `App.tsx`

```tsx
import { createPlugin } from '@naap/plugin-sdk';
import MyPage from './pages/MyPage';

const plugin = createPlugin({
  name: 'my-plugin',
  version: '1.0.0',
  routes: ['/my-plugin', '/my-plugin/*'],
  App: MyPage,
});

export const mount = plugin.mount;
export default plugin;
```

## 4. Add features incrementally

```bash
# Add an API endpoint
naap-plugin add endpoint users --crud

# Add a database model (monorepo only)
naap-plugin add model Todo title:String done:Boolean
```

## 5. Test, build, publish

```bash
naap-plugin test
naap-plugin build
naap-plugin publish
```

## 6. Register your team (monorepo contributors)

Add a CODEOWNERS entry and labeler entry, then open a PR:

```
# .github/CODEOWNERS
/plugins/my-plugin/    @livepeer/my-team

# .github/labeler.yml
plugin:my-plugin:
  - plugins/my-plugin/**
```

After merge, your team owns the plugin directory autonomously.

## Need more detail?

- Architecture deep-dive: `docs/PLUGIN_ARCHITECTURE.md`
- Publishing workflow: `docs/plugin-publishing-guide.md`
- SDK reference: `packages/plugin-sdk/DEVELOPER_GUIDE.md`
