#!/usr/bin/env node
// Plugin Discovery - reads plugin.json files and outputs structured data.
//
// Usage:
//   node bin/discover-plugins.cjs                  # JSON array of all plugins
//   node bin/discover-plugins.cjs --concurrently   # concurrently command spec for backends
//   node bin/discover-plugins.cjs --ports          # space-separated list of all dev ports
//   node bin/discover-plugins.cjs --only=a,b       # filter to named plugins only
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const pluginsDir = path.join(ROOT, 'plugins');

const args = process.argv.slice(2);
const onlyFlag = args.find(a => a.startsWith('--only='));
const onlyNames = onlyFlag ? onlyFlag.split('=')[1].split(',').filter(Boolean) : null;

function discoverPlugins() {
  const plugins = [];
  let entries;
  try { entries = fs.readdirSync(pluginsDir, { withFileTypes: true }); }
  catch { return plugins; }

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const pjPath = path.join(pluginsDir, entry.name, 'plugin.json');
    if (!fs.existsSync(pjPath)) continue;
    try {
      const pj = JSON.parse(fs.readFileSync(pjPath, 'utf8'));
      const plugin = {
        name: pj.name || entry.name,
        displayName: pj.displayName || pj.name || entry.name,
        dir: entry.name,
        frontendPort: pj.frontend?.devPort || null,
        backendPort: pj.backend?.devPort || null,
        healthCheck: pj.backend?.healthCheck || '/healthz',
        apiPrefix: pj.backend?.apiPrefix || null,
        hasBackend: fs.existsSync(path.join(pluginsDir, entry.name, 'backend')),
        hasFrontend: fs.existsSync(path.join(pluginsDir, entry.name, 'frontend')),
      };
      if (onlyNames && !onlyNames.includes(plugin.name)) continue;
      plugins.push(plugin);
    } catch { /* skip malformed plugin.json */ }
  }
  return plugins;
}

const plugins = discoverPlugins();

if (args.includes('--concurrently')) {
  // Output concurrently-compatible name:command pairs for backends that have ports
  const specs = plugins
    .filter(p => p.hasBackend && p.backendPort)
    .map(p => ({
      name: `${p.name}-svc`,
      command: `cd plugins/${p.dir}/backend && DATABASE_URL="postgresql://postgres:postgres@localhost:5432/naap" PORT=${p.backendPort} npm run dev`,
    }));
  // Output as JSON for concurrently --names/--commands
  process.stdout.write(JSON.stringify(specs));
} else if (args.includes('--ports')) {
  const ports = [];
  for (const p of plugins) {
    if (p.backendPort) ports.push(p.backendPort);
    if (p.frontendPort) ports.push(p.frontendPort);
  }
  process.stdout.write(ports.join(' '));
} else if (args.includes('--backend-ports')) {
  const ports = plugins.filter(p => p.backendPort).map(p => p.backendPort);
  process.stdout.write(ports.join(' '));
} else if (args.includes('--health-urls')) {
  // Output wait-on compatible URLs for all backends
  const urls = plugins
    .filter(p => p.hasBackend && p.backendPort)
    .map(p => `http-get://localhost:${p.backendPort}${p.healthCheck}`);
  process.stdout.write(urls.join(' '));
} else {
  process.stdout.write(JSON.stringify(plugins, null, 2));
}
