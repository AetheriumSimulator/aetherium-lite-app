#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NTDLL="${1:-${ROOT_DIR}/proton/src/main/resources/rawfile/runtime/proton/files/lib/wine/x86_64-unix/ntdll.so}"

patch_bytes() {
  local name="$1"
  local offset="$2"
  local expected="$3"
  local patched="$4"
  local length actual

  length=$((${#expected} / 2))
  actual="$(xxd -p -l "${length}" -s "${offset}" "${NTDLL}")"

  if [[ "${actual}" == "${patched}" ]]; then
    echo "[proton-runtime] ntdll ${name} already patched: ${NTDLL}"
    return
  fi

  if [[ "${actual}" != "${expected}" ]]; then
    printf '[proton-runtime] refusing to patch unexpected ntdll bytes for %s at 0x%x: %s\n' \
      "${name}" "${offset}" "${actual}" >&2
    exit 1
  fi

  printf '%s' "${patched}" | xxd -r -p | dd of="${NTDLL}" bs=1 seek="${offset}" conv=notrunc status=none
  echo "[proton-runtime] patched ntdll ${name}: ${NTDLL}"
}

# Proton's current x86_64 ntdll build inlines run_wineboot() into
# init_startup_info(). Until we can rebuild the full Proton redist locally,
# skip the wineboot process creation path with a tiny, version-checked patch:
#   0x179ef: call NtCreateEvent -> jmp 0x17a1b
patch_bytes "wineboot skip" $((0x179ef)) \
  "e86c090400" \
  "e927000000"

# HarmonyOS app sandboxes can leave dosdevices as placeholder files instead of
# Linux symlinks. In that state find_drive_nt_root() can return success with a
# null output pointer, while get_full_path() assumes the pointer is valid:
#   0x23105: status-only check -> null-root fallback check
patch_bytes "get_full_path null-root fallback" $((0x23105)) \
  "85c00f851ffeffff410fb7176685d20f8570ffffff660f1f440000" \
  "4d85ff7505e91dfeffff410fb7176685d20f856effffff90909090"
