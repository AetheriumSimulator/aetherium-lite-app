#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WIN32U="${1:-${ROOT_DIR}/proton/src/main/resources/rawfile/runtime/proton/files/lib/wine/x86_64-unix/win32u.so}"

patch_bytes() {
  local name="$1"
  local offset="$2"
  local expected="$3"
  local patched="$4"
  local length actual

  length=$((${#expected} / 2))
  actual="$(xxd -p -l "${length}" -s "${offset}" "${WIN32U}")"

  if [[ "${actual}" == "${patched}" ]]; then
    echo "[proton-runtime] win32u ${name} already patched: ${WIN32U}"
    return
  fi

  if [[ "${actual}" != "${expected}" ]]; then
    printf '[proton-runtime] refusing to patch unexpected win32u bytes for %s at 0x%x: %s\n' \
      "${name}" "${offset}" "${actual}" >&2
    exit 1
  fi

  printf '%s' "${patched}" | xxd -r -p | dd of="${WIN32U}" bs=1 seek="${offset}" conv=notrunc status=none
  echo "[proton-runtime] patched win32u ${name}: ${WIN32U}"
}

if grep -a -q "HMOS wineonarkui: registered builtin control classes" "${WIN32U}"; then
  echo "[proton-runtime] win32u already carries source-level HMOS bootstrap patches: ${WIN32U}"
  exit 0
fi

# register_builtins() registers the Win32 builtin control classes and then calls
# KeUserModeCallback(NtUserInitBuiltinClasses) for the uxtheme preload path. On
# HarmonyOS in-process Wine that callback boundary can terminate startup before
# the app-level RegisterClassW returns. The builtin classes are already created,
# so skip the callback for the native ArkUI display-driver bootstrap.
patch_bytes "skip builtin user callback" $((0x362ab)) \
  "e82084ffff" \
  "9090909090"

# Let HMOS use the no-driver fallback as a bootstrap display driver. This keeps
# CreateWindowExW alive until wineonarkui.drv provides a real XComponent backed
# CreateWindow path.
patch_bytes "allow nodrv CreateWindow" $((0x940f0)) \
  "55be01000000" \
  "b801000000c3"
