#!/bin/bash

# NAAP Platform Manager — Development Tooling (Simplified)
# =========================================================
# Uses `concurrently` to manage all dev processes instead of custom PID tracking.
#
# Usage:
#   ./bin/start.sh                 Start shell + core services + auto-detected plugins
#   ./bin/start.sh --all           Start everything (all plugin backends)
#   ./bin/start.sh <plugin> ...    Start shell + core + named plugins
#   ./bin/start.sh status          Show running services
#   ./bin/start.sh help            Show all options
#
# Stop:
#   ./bin/stop.sh                  Stop all services
#   ./bin/stop.sh --infra          Also stop Docker containers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$ROOT_DIR/logs"

SHELL_PORT="${SHELL_PORT:-3000}"
BASE_SVC_PORT="${BASE_SVC_PORT:-4000}"
PLUGIN_SERVER_PORT="${PLUGIN_SERVER_PORT:-3100}"
UNIFIED_DB_URL="postgresql://postgres:postgres@localhost:5432/naap"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

mkdir -p "$LOG_DIR"

###############################################################################
# PRE-FLIGHT
###############################################################################

preflight_check() {
  local ok=true
  command -v node >/dev/null 2>&1 || { log_error "node not found. Install Node.js 20+"; ok=false; }
  command -v npm  >/dev/null 2>&1 || { log_error "npm not found."; ok=false; }
  [ "$ok" = false ] && exit 1

  local node_major
  node_major=$(node -v | sed 's/v\([0-9]*\).*/\1/')
  [ "$node_major" -lt 20 ] 2>/dev/null && { log_error "Node.js v20+ required (found $(node -v))"; exit 1; }

  # Auto-install on fresh clone
  if [ ! -d "$ROOT_DIR/node_modules" ]; then
    log_warn "node_modules not found — running npm install..."
    cd "$ROOT_DIR" && npm install
    log_success "Dependencies installed"
  fi

  # Ensure workspace packages are built
  if [ ! -f "$ROOT_DIR/packages/plugin-build/dist/index.js" ] || \
     [ ! -f "$ROOT_DIR/packages/cache/dist/index.js" ]; then
    log_info "Building workspace packages..."
    node "$ROOT_DIR/bin/bootstrap-workspace-packages.cjs" || { log_error "Bootstrap failed"; exit 1; }
  fi

  # Check concurrently is available
  if ! npx --no concurrently --version >/dev/null 2>&1; then
    log_error "concurrently not found. Run: npm install"
    exit 1
  fi
}

###############################################################################
# DOCKER INFRASTRUCTURE
###############################################################################

_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    log_error "Docker Compose not found."; return 1
  fi
}

ensure_database() {
  if ! docker info >/dev/null 2>&1; then
    log_warn "Docker not running — database will not be available."
    return 1
  fi

  local container="naap-db"
  if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then
    log_success "Database already running"
    return 0
  fi

  log_info "Starting database..."
  cd "$ROOT_DIR" && _docker_compose up -d database

  log_info "Waiting for database..."
  for i in $(seq 1 30); do
    docker exec "$container" pg_isready -U postgres >/dev/null 2>&1 && { log_success "Database ready"; return 0; }
    sleep 1
  done
  log_error "Database failed to start within 30s"
  return 1
}

###############################################################################
# PRISMA SYNC (schema + seed)
###############################################################################

sync_database() {
  local schema_file="$ROOT_DIR/packages/database/prisma/schema.prisma"
  local sync_marker="$ROOT_DIR/.prisma-synced"

  # Run init-schemas.sql to ensure all PG schemas exist
  if [ -f "$ROOT_DIR/docker/init-schemas.sql" ]; then
    docker exec -i naap-db psql -U postgres -d naap < "$ROOT_DIR/docker/init-schemas.sql" >/dev/null 2>&1 || true
  fi

  # Skip if schema hasn't changed (hash-based)
  local schema_hash=""
  if command -v md5sum >/dev/null 2>&1; then
    schema_hash=$(md5sum "$schema_file" 2>/dev/null | cut -d' ' -f1)
  elif command -v md5 >/dev/null 2>&1; then
    schema_hash=$(md5 -q "$schema_file" 2>/dev/null)
  fi

  local cached_hash=""
  [ -f "$sync_marker" ] && cached_hash=$(cat "$sync_marker" 2>/dev/null)

  if [ -n "$schema_hash" ] && [ "$schema_hash" = "$cached_hash" ] && \
     [ -f "$ROOT_DIR/node_modules/.prisma/client/index.js" ]; then
    log_success "Prisma client up to date (schema unchanged)"
    return 0
  fi

  log_info "Syncing Prisma..."
  cd "$ROOT_DIR/packages/database"
  npx prisma generate >/dev/null 2>&1 || { log_error "Prisma generate failed"; return 1; }
  DATABASE_URL="$UNIFIED_DB_URL" npx prisma db push --skip-generate --accept-data-loss >/dev/null 2>&1 && \
    log_success "Schema pushed" || log_warn "Schema push had issues"

  [ -n "$schema_hash" ] && echo "$schema_hash" > "$sync_marker"

  # Seed if needed (quick check)
  local user_count
  user_count=$(docker exec naap-db psql -U postgres -d naap -t -c "SELECT count(*) FROM \"User\"" 2>/dev/null | tr -d ' ')
  if [ "$user_count" = "0" ] 2>/dev/null; then
    log_info "Seeding database..."
    cd "$ROOT_DIR/apps/web-next"
    DATABASE_URL="$UNIFIED_DB_URL" npx tsx prisma/seed.ts > "$LOG_DIR/seed.log" 2>&1 && \
      log_success "Database seeded" || log_warn "Seed had issues"
  fi

  # Sync plugin registry
  cd "$ROOT_DIR"
  DATABASE_URL="$UNIFIED_DB_URL" npx tsx bin/sync-plugin-registry.ts > "$LOG_DIR/sync-plugins.log" 2>&1 || true
}

###############################################################################
# .ENV FILES
###############################################################################

ensure_env_files() {
  # base-svc
  [ ! -f "$ROOT_DIR/services/base-svc/.env" ] && \
    printf 'DATABASE_URL="%s"\nPORT=%s\n' "$UNIFIED_DB_URL" "$BASE_SVC_PORT" > "$ROOT_DIR/services/base-svc/.env"

  # apps/web-next
  [ ! -f "$ROOT_DIR/apps/web-next/.env.local" ] && cat > "$ROOT_DIR/apps/web-next/.env.local" <<EOF
NEXT_PUBLIC_APP_URL=http://localhost:$SHELL_PORT
NEXTAUTH_SECRET=dev-secret-change-me-in-production-min-32-chars
DATABASE_URL=$UNIFIED_DB_URL
BASE_SVC_URL=http://localhost:$BASE_SVC_PORT
PLUGIN_SERVER_URL=http://localhost:$PLUGIN_SERVER_PORT
EOF

  # Plugin backends
  for pj in "$ROOT_DIR/plugins"/*/plugin.json; do
    [ -f "$pj" ] || continue
    local pdir=$(dirname "$pj")
    [ -d "$pdir/backend" ] || continue
    [ -f "$pdir/backend/.env" ] && continue
    local port
    port=$(node -e "console.log(require('$pj').backend?.devPort || '')" 2>/dev/null)
    [ -z "$port" ] && continue
    printf 'DATABASE_URL="%s"\nPORT=%s\n' "$UNIFIED_DB_URL" "$port" > "$pdir/backend/.env"
  done
}

###############################################################################
# PLUGIN BUILD CHECK
###############################################################################

ensure_plugins_built() {
  # Remove stale Vercel-only CDN artifacts
  [ -d "$ROOT_DIR/apps/web-next/public/cdn" ] && rm -rf "$ROOT_DIR/apps/web-next/public/cdn"

  log_info "Checking plugin builds..."
  local to_build=()
  for pj in "$ROOT_DIR/plugins"/*/plugin.json; do
    [ -f "$pj" ] || continue
    local pdir=$(dirname "$pj")
    local pname=$(basename "$pdir")
    [ -d "$pdir/frontend/dist/production" ] && continue
    [ -d "$pdir/frontend" ] || continue
    to_build+=("$pname")
  done

  if [ ${#to_build[@]} -eq 0 ]; then
    log_success "All plugins built"
    return 0
  fi

  log_warn "Building plugins: ${to_build[*]}"
  for p in "${to_build[@]}"; do
    cd "$ROOT_DIR/plugins/$p/frontend" && npm run build > "$LOG_DIR/${p}-build.log" 2>&1 && \
      log_success "Built $p" || log_warn "Build failed for $p (check logs/${p}-build.log)"
    # Copy to CDN location
    local src="$ROOT_DIR/plugins/$p/frontend/dist/production"
    local cdn="$ROOT_DIR/dist/plugins/$p/1.0.0"
    [ -d "$src" ] && { mkdir -p "$cdn"; cp -r "$src/"* "$cdn/" 2>/dev/null || true; }
  done
}

###############################################################################
# START WITH CONCURRENTLY
###############################################################################

get_frontend_dir() {
  [ -d "$ROOT_DIR/apps/web" ] && echo "$ROOT_DIR/apps/web" || echo "$ROOT_DIR/apps/web-next"
}

build_concurrently_args() {
  local mode=$1  # "all", "none", or comma-separated plugin names
  shift
  local names=() commands=()

  # Core: Next.js shell
  names+=("shell")
  local fdir=$(get_frontend_dir)
  commands+=("cd $fdir && WATCHPACK_POLLING=1000 PORT=$SHELL_PORT npx next dev -p $SHELL_PORT")

  # Core: base-svc
  names+=("base-svc")
  commands+=("cd $ROOT_DIR/services/base-svc && DATABASE_URL=\"$UNIFIED_DB_URL\" PORT=$BASE_SVC_PORT npm run dev")

  # Core: plugin-server
  names+=("plugin-svc")
  commands+=("cd $ROOT_DIR/services/plugin-server && PLUGIN_SERVER_PORT=$PLUGIN_SERVER_PORT npm run dev")

  # Plugin backends (based on mode)
  if [ "$mode" != "none" ]; then
    local plugin_json_output
    if [ "$mode" = "all" ]; then
      plugin_json_output=$(node "$SCRIPT_DIR/discover-plugins.cjs" --concurrently)
    else
      plugin_json_output=$(node "$SCRIPT_DIR/discover-plugins.cjs" --only="$mode" --concurrently)
    fi

    # Parse JSON array of {name, command} objects
    local count
    count=$(echo "$plugin_json_output" | node -e "
      const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      console.log(d.length);
    ")

    if [ "$count" -gt 0 ]; then
      eval "$(echo "$plugin_json_output" | node -e "
        const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
        d.forEach(s => {
          console.log('names+=(\"' + s.name + '\")');
          console.log('commands+=(\"' + s.command.replace(/\"/g, '\\\\\"') + '\")');
        });
      ")"
    fi
  fi

  # Build concurrently arguments
  local args=("--kill-others-on-fail" "--prefix" "[{name}]" "--prefix-colors" "auto")

  # Add --names
  local names_str=$(IFS=','; echo "${names[*]}")
  args+=("--names" "$names_str")

  # Add commands
  for cmd in "${commands[@]}"; do
    args+=("$cmd")
  done

  printf '%s\n' "${args[@]}"
}

cmd_start() {
  local mode=$1  # "all", "none", or comma-separated plugin names
  local t=$(date +%s)

  log_section "Pre-flight"
  preflight_check

  log_section "Infrastructure"
  ensure_env_files
  ensure_database || true

  if [ "$SKIP_DB" != "1" ]; then
    sync_database || true
  fi

  log_section "Plugin Builds"
  ensure_plugins_built

  log_section "Starting Services"
  if [ "$mode" = "none" ]; then
    log_info "Starting shell + core services..."
  elif [ "$mode" = "all" ]; then
    log_info "Starting all services + all plugin backends..."
  else
    log_info "Starting shell + core + plugins: ${BOLD}$mode${NC}..."
  fi

  echo ""
  log_info "All output below is from concurrently. Press Ctrl+C to stop everything."
  echo ""

  cd "$ROOT_DIR"

  # Build the concurrently command
  local -a cc_names=() cc_commands=()

  # Core: Next.js shell
  cc_names+=("shell")
  local fdir=$(get_frontend_dir)
  cc_commands+=("cd $fdir && WATCHPACK_POLLING=1000 PORT=$SHELL_PORT npx next dev -p $SHELL_PORT")

  # Core: base-svc
  cc_names+=("base-svc")
  cc_commands+=("cd $ROOT_DIR/services/base-svc && DATABASE_URL='$UNIFIED_DB_URL' PORT=$BASE_SVC_PORT npm run dev")

  # Core: plugin-server
  cc_names+=("plugin-svc")
  cc_commands+=("cd $ROOT_DIR/services/plugin-server && PLUGIN_SERVER_PORT=$PLUGIN_SERVER_PORT npm run dev")

  # Plugin backends
  if [ "$mode" != "none" ]; then
    local plugin_data
    if [ "$mode" = "all" ]; then
      plugin_data=$(node "$SCRIPT_DIR/discover-plugins.cjs" --concurrently)
    else
      plugin_data=$(node "$SCRIPT_DIR/discover-plugins.cjs" --only="$mode" --concurrently)
    fi

    while IFS= read -r line; do
      local pname pcmd
      pname=$(echo "$line" | node -e "const l=require('fs').readFileSync('/dev/stdin','utf8').trim(); if(l) console.log(JSON.parse(l).name)" 2>/dev/null) || continue
      pcmd=$(echo "$line" | node -e "const l=require('fs').readFileSync('/dev/stdin','utf8').trim(); if(l) console.log(JSON.parse(l).command)" 2>/dev/null) || continue
      [ -n "$pname" ] && cc_names+=("$pname") && cc_commands+=("$pcmd")
    done < <(echo "$plugin_data" | node -e "
      const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      d.forEach(s => console.log(JSON.stringify(s)));
    ")
  fi

  local names_csv=$(IFS=','; echo "${cc_names[*]}")

  # Run concurrently with all services
  npx concurrently \
    --prefix "[{name}]" \
    --prefix-colors "auto" \
    --names "$names_csv" \
    --kill-others-on-fail \
    "${cc_commands[@]}"
}

###############################################################################
# STATUS
###############################################################################

cmd_status() {
  echo ""
  echo -e "${BOLD}NAAP Platform Status${NC}"
  echo -e "${DIM}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo ""
  printf "  ${BOLD}%-25s %-8s %-10s${NC}\n" "SERVICE" "PORT" "HEALTH"
  printf "  %-25s %-8s %-10s\n" "-------------------------" "--------" "----------"

  _check() {
    local name=$1 port=$2 path=${3:-}
    local url="http://localhost:${port}${path}"
    local status
    if [ -n "$path" ]; then
      status=$(curl -s -o /dev/null -w "%{http_code}" "$url" --connect-timeout 2 2>/dev/null) || status="000"
    else
      status=$(curl -s -o /dev/null -w "%{http_code}" "$url" --connect-timeout 2 2>/dev/null) || status="000"
    fi
    local hs
    case "$status" in
      200) hs="${GREEN}healthy${NC}" ;;
      000) hs="${DIM}stopped${NC}" ;;
      *)   hs="${YELLOW}HTTP $status${NC}" ;;
    esac
    printf "  %-25s %-8s %b\n" "$name" "$port" "$hs"
  }

  _check "Shell (Next.js)" "$SHELL_PORT" ""
  _check "Base Service" "$BASE_SVC_PORT" "/healthz"
  _check "Plugin Server" "$PLUGIN_SERVER_PORT" "/healthz"

  echo ""
  printf "  ${BOLD}%-25s${NC}\n" "PLUGIN BACKENDS"
  printf "  %-25s %-8s %-10s\n" "-------------------------" "--------" "----------"

  local plugins
  plugins=$(node "$SCRIPT_DIR/discover-plugins.cjs" 2>/dev/null) || plugins="[]"
  echo "$plugins" | node -e "
    const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    d.filter(p => p.backendPort).forEach(p => {
      console.log(p.displayName + '|' + p.backendPort + '|' + p.healthCheck);
    });
  " 2>/dev/null | while IFS='|' read -r name port hc; do
    _check "$name" "$port" "$hc"
  done

  echo ""
  if docker info >/dev/null 2>&1; then
    local cnt=$(docker ps --filter "name=naap-" --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${BOLD}Infrastructure:${NC} $cnt Docker container(s)"
    [ "$cnt" -gt 0 ] && docker ps --filter "name=naap-" --format "    {{.Names}} ({{.Status}})" 2>/dev/null
  else
    echo -e "  ${BOLD}Infrastructure:${NC} ${RED}Docker not running${NC}"
  fi
  echo ""
}

###############################################################################
# LIST & LOGS
###############################################################################

cmd_list() {
  echo ""
  echo -e "${BOLD}Available Plugins${NC}"
  echo ""
  node "$SCRIPT_DIR/discover-plugins.cjs" | node -e "
    const d = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    console.log('  ' + 'NAME'.padEnd(25) + 'FRONTEND'.padEnd(12) + 'BACKEND'.padEnd(12));
    console.log('  ' + '-'.repeat(25) + '-'.repeat(12) + '-'.repeat(12));
    d.forEach(p => {
      console.log('  ' + (p.displayName||p.name).padEnd(25) + String(p.frontendPort||'N/A').padEnd(12) + String(p.backendPort||'N/A').padEnd(12));
    });
  "
  echo ""
}

cmd_logs() {
  local svc=$1
  if [ -z "$svc" ]; then
    echo "Available logs:"
    ls -1 "$LOG_DIR"/*.log 2>/dev/null | while read -r f; do echo "  $(basename "$f" .log)"; done
    echo ""
    echo "Usage: ./bin/start.sh logs <name>"
    return
  fi
  local lf="$LOG_DIR/${svc}.log"
  [ ! -f "$lf" ] && lf="$LOG_DIR/${svc}-svc.log"
  [ ! -f "$lf" ] && lf="$LOG_DIR/${svc}-web.log"
  [ -f "$lf" ] && tail -f "$lf" || log_error "No log found for: $svc"
}

###############################################################################
# HELP
###############################################################################

show_help() {
  cat <<'HELP'

NAAP Platform Manager (Simplified)

Usage: ./bin/start.sh [command] [options]

Commands:
  (default)              Start shell + core (auto-detects changed plugins)
  --all                  Start everything (all plugin backends)
  <plugin> [plugin...]   Start shell + core + named plugin backends
  status                 Show status of all services
  list                   List available plugins
  logs [service]         Tail logs for a service
  help                   Show this help

Options:
  --skip-db              Skip database sync (trust existing state)

Stop:
  ./bin/stop.sh          Stop all services
  ./bin/stop.sh --infra  Also stop Docker containers

Environment:
  SHELL_PORT=N           Next.js shell port (default: 3000)
  BASE_SVC_PORT=N        Base service port (default: 4000)
  PLUGIN_SERVER_PORT=N   Plugin server port (default: 3100)

Quick Start:
  ./bin/start.sh                  # Smart start (auto-detects changes)
  ./bin/start.sh community        # Shell + community backend
  ./bin/start.sh --all            # Everything

First time? Just run ./bin/start.sh — setup is automatic.

HELP
}

###############################################################################
# MAIN
###############################################################################

SKIP_DB="${SKIP_DB:-0}"
COMMAND_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --skip-db)    SKIP_DB=1 ;;
    *)            COMMAND_ARGS+=("$arg") ;;
  esac
done

COMMAND="${COMMAND_ARGS[0]:-}"

case "$COMMAND" in
  -h|--help|help)
    show_help ;;
  status)
    cmd_status ;;
  list)
    cmd_list ;;
  logs)
    cmd_logs "${COMMAND_ARGS[1]:-}" ;;
  --all)
    cmd_start "all" ;;
  --infra)
    preflight_check
    ensure_env_files
    ensure_database
    sync_database
    log_success "Infrastructure ready." ;;
  "")
    # Smart default: start shell + core, no plugin backends
    cmd_start "none" ;;
  *)
    # Treat arguments as plugin names
    if [ -d "$ROOT_DIR/plugins/$COMMAND" ]; then
      local_plugins="$COMMAND"
      for extra in "${COMMAND_ARGS[@]:1}"; do
        [ -d "$ROOT_DIR/plugins/$extra" ] && local_plugins="$local_plugins,$extra" || log_warn "Unknown plugin: $extra"
      done
      cmd_start "$local_plugins"
    else
      log_error "Unknown command: $COMMAND"
      show_help
      exit 1
    fi ;;
esac
