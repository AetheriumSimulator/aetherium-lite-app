#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_PROXY_HOST="${HOST_PROXY_HOST:-$(ip route | awk '/default/ { print $3; exit }')}"
HOST_PROXY_PORT="${HOST_PROXY_PORT:-7897}"

if [[ -z "${HOST_PROXY_HOST}" ]]; then
  printf '[proton-runtime] failed to detect host proxy address; set HOST_PROXY_HOST or PROTON_RUNTIME_PROXY\n' >&2
  exit 1
fi

export PROTON_RUNTIME_PROXY="${PROTON_RUNTIME_PROXY:-http://${HOST_PROXY_HOST}:${HOST_PROXY_PORT}}"
exec "${SCRIPT_DIR}/fetch_sources.sh" "$@"
