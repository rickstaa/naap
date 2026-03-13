#!/bin/bash

# NAAP Platform — Stop Script (Development Tooling)
# ==================================================
# Kills all NAAP dev processes by scanning known ports.
# Works regardless of how services were started (concurrently, manual, etc.)
#
# Usage:
#   ./bin/stop.sh              Stop all NAAP services
#   ./bin/stop.sh <plugin>     Stop a specific plugin
#   ./bin/stop.sh --infra      Also stop Docker containers

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
GRACEFUL_TIMEOUT="${GRACEFUL_TIMEOUT:-5}"

SHELL_PORT="${SHELL_PORT:-3000}"
BASE_SVC_PORT="${BASE_SVC_PORT:-4000}"
PLUGIN_SERVER_PORT="${PLUGIN_SERVER_PORT:-3100}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

kill_port() {
  local port=$1 name=$2
  local pids
  pids=$(lsof -ti:"$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "$pids" | xargs kill -TERM 2>/dev/null || true
    sleep 1
    # Force-kill survivors
    pids=$(lsof -ti:"$port" 2>/dev/null || true)
    [ -n "$pids" ] && echo "$pids" | xargs kill -9 2>/dev/null || true
    log_success "Stopped ${name:-port $port}"
    return 0
  fi
  return 1
}

stop_all() {
  echo ""
  log_info "Stopping all NAAP Platform services..."
  local killed=0

  # Kill tracked PIDs (backward compat with old .pids file)
  if [ -f "$ROOT_DIR/.pids" ] && [ -s "$ROOT_DIR/.pids" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local pid=$(echo "$line" | cut -d' ' -f1)
      kill -0 "$pid" 2>/dev/null && { kill -TERM "$pid" 2>/dev/null || true; ((killed++)); }
    done < "$ROOT_DIR/.pids"
    : > "$ROOT_DIR/.pids"
    [ $killed -gt 0 ] && sleep "$GRACEFUL_TIMEOUT"
  fi

  # Kill by port — the reliable method
  kill_port "$SHELL_PORT" "Shell (Next.js)" && ((killed++)) || true
  kill_port "$BASE_SVC_PORT" "Base Service" && ((killed++)) || true
  kill_port "$PLUGIN_SERVER_PORT" "Plugin Server" && ((killed++)) || true

  # Kill plugin backends by discovered ports
  if [ -f "$SCRIPT_DIR/discover-plugins.cjs" ]; then
    local ports
    ports=$(node "$SCRIPT_DIR/discover-plugins.cjs" --ports 2>/dev/null) || ports=""
    for port in $ports; do
      kill_port "$port" "plugin on :$port" && ((killed++)) || true
    done
  fi

  echo ""
  if [ $killed -gt 0 ]; then
    log_success "All NAAP services stopped"
  else
    log_info "No NAAP services were running"
  fi
}

stop_plugin() {
  local name=$1
  [ ! -d "$ROOT_DIR/plugins/$name" ] && { log_error "Plugin not found: $name"; return 1; }

  local port
  port=$(node -e "const p=require('$ROOT_DIR/plugins/$name/plugin.json'); console.log(p.backend?.devPort||'')" 2>/dev/null)
  if [ -n "$port" ]; then
    kill_port "$port" "$name backend" || log_info "$name was not running"
  else
    log_warn "No backend port found for $name"
  fi
}

stop_infra() {
  log_info "Stopping Docker containers..."
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    cd "$ROOT_DIR" || true
    docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
    log_success "Docker containers stopped"
  else
    log_warn "Docker not available"
  fi
}

show_help() {
  cat <<'HELP'

NAAP Platform — Stop (Development Tooling)

Usage: ./bin/stop.sh [options]

  (no options)     Stop all NAAP services
  <plugin> ...     Stop specific plugin(s)
  --infra          Stop all services + Docker containers
  --help           Show this help

Environment:
  GRACEFUL_TIMEOUT=N   Seconds before force-kill (default: 5)

HELP
}

case "${1:-}" in
  --infra)    stop_all; stop_infra ;;
  --help|-h)  show_help ;;
  "")         stop_all ;;
  *)          for p in "$@"; do
                [ -d "$ROOT_DIR/plugins/$p" ] && stop_plugin "$p" || log_error "Unknown plugin: $p"
              done ;;
esac
