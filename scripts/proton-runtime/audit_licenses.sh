#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${ROOT_DIR}/third_party/proton-runtime/src"
LICENSE_DIR="${PROTON_RUNTIME_LICENSE_DIR:-${ROOT_DIR}/LICENSES}"

show_license_files() {
  local name="$1"
  local dir="${SRC_DIR}/${name}"
  local bundled_dir="${LICENSE_DIR}/${name}"

  printf '\n[%s]\n' "${name}"
  if [[ ! -d "${dir}" ]]; then
    printf 'missing checkout: %s\n' "${dir}"
    if [[ -d "${bundled_dir}" ]]; then
      printf 'bundled license copies:\n'
      find "${bundled_dir}" -maxdepth 1 -type f -printf '  %P\n' | sort
    fi
    return
  fi

  find "${dir}" -maxdepth 1 -type f \
    \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' -o -iname 'AUTHORS*' -o -iname 'PATENTS*' \) \
    -printf '%P\n' | sort
}

show_license_files proton
show_license_files box64
show_license_files wine
show_license_files dxvk
show_license_files vkd3d-proton
