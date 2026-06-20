#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
USER32="${1:-${ROOT_DIR}/proton/src/main/resources/rawfile/runtime/proton/files/lib/wine/x86_64-windows/user32.dll}"

patch_bytes() {
  local name="$1"
  local offset="$2"
  local expected="$3"
  local patched="$4"
  local length actual

  length=$((${#expected} / 2))
  actual="$(xxd -p -l "${length}" -s "${offset}" "${USER32}")"

  if [[ "${actual}" == "${patched}" ]]; then
    echo "[proton-runtime] user32 ${name} already patched: ${USER32}"
    return
  fi

  if [[ "${actual}" != "${expected}" ]]; then
    printf '[proton-runtime] refusing to patch unexpected user32 bytes for %s at 0x%x: %s\n' \
      "${name}" "${offset}" "${actual}" >&2
    exit 1
  fi

  printf '%s' "${patched}" | xxd -r -p | dd of="${USER32}" bs=1 seek="${offset}" conv=notrunc status=none
  echo "[proton-runtime] patched user32 ${name}: ${USER32}"
}

# User32InitBuiltinClasses() only preloads uxtheme.dll and returns 0. On
# HarmonyOS in-process Wine this preload can end the process before app-level
# RegisterClassW returns, either through the missing builtin uxtheme.so path or
# through a native PE stub. Skip it until wineonarkui.drv owns theming.
patch_bytes "skip uxtheme preload" $((0x4de80)) \
  "555348" \
  "31c0c3"
