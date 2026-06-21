#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts/proton-runtime"
SRC_DIR="${ROOT_DIR}/third_party/proton-runtime/src"

mode="${1:-all}"

fail_missing_checkout() {
  local component="$1"
  local expected="$2"

  printf '[proton-runtime] missing %s source file: %s\n' "${component}" "${expected}" >&2
  printf '[proton-runtime] run scripts/proton-runtime/bootstrap_runtime_sources.sh first.\n' >&2
  printf '[proton-runtime] fetch_sources.sh alone only downloads upstream sources; bootstrap also applies Aetherium patches.\n' >&2
  exit 1
}

apply_component_patch() {
  local component="$1"

  PROTON_RUNTIME_SOURCE_PATCH_DIR="${PROTON_RUNTIME_SOURCE_PATCH_DIR:-}" \
    "${SCRIPT_DIR}/apply_corresponding_source_patches.sh" "${component}"
}

ensure_box64() {
  local box64_dir="${SRC_DIR}/box64"
  local wrapped="${box64_dir}/src/wrapped/wrappedlibc.c"
  local hmos_entry="${box64_dir}/src/hmos_inprocess.c"
  local cmake="${box64_dir}/CMakeLists.txt"

  [[ -f "${wrapped}" ]] || fail_missing_checkout "Box64 upstream" "${wrapped}"

  if [[ -f "${hmos_entry}" ]] &&
     grep -q 'box64_hmos_core' "${cmake}" &&
     grep -q 'box64_hmos_inprocess_mode' "${wrapped}"; then
    printf '[proton-runtime] Box64 HMOS in-process sources ready: %s\n' "${box64_dir}"
    return
  fi

  printf '[proton-runtime] Box64 checkout is missing HMOS in-process patch files; applying corresponding-source patch.\n'
  apply_component_patch box64

  [[ -f "${hmos_entry}" ]] || {
    printf '[proton-runtime] Box64 patch did not create expected file: %s\n' "${hmos_entry}" >&2
    exit 1
  }
  grep -q 'box64_hmos_core' "${cmake}" || {
    printf '[proton-runtime] Box64 patch did not add box64_hmos_core CMake target: %s\n' "${cmake}" >&2
    exit 1
  }
  grep -q 'box64_hmos_inprocess_mode' "${wrapped}" || {
    printf '[proton-runtime] Box64 patch did not update wrappedlibc.c with HMOS process hooks: %s\n' "${wrapped}" >&2
    exit 1
  }

  printf '[proton-runtime] Box64 HMOS in-process sources ready: %s\n' "${box64_dir}"
}

ensure_wine() {
  local wine_dir="${SRC_DIR}/wine"
  local process_c="${wine_dir}/dlls/ntdll/unix/process.c"

  [[ -f "${process_c}" ]] || fail_missing_checkout "Wine upstream" "${process_c}"

  if grep -q 'WINE_HMOS_PROCESS_BROKER_DIR' "${process_c}"; then
    printf '[proton-runtime] Wine HMOS source patch ready: %s\n' "${wine_dir}"
    return
  fi

  printf '[proton-runtime] Wine checkout is missing HMOS source patch; applying corresponding-source patch.\n'
  apply_component_patch wine

  grep -q 'WINE_HMOS_PROCESS_BROKER_DIR' "${process_c}" || {
    printf '[proton-runtime] Wine patch did not add HMOS process broker hooks: %s\n' "${process_c}" >&2
    exit 1
  }

  printf '[proton-runtime] Wine HMOS source patch ready: %s\n' "${wine_dir}"
}

case "${mode}" in
  box64)
    ensure_box64
    ;;
  wine)
    ensure_wine
    ;;
  all)
    ensure_box64
    ensure_wine
    ;;
  *)
    printf '[proton-runtime] usage: %s [all|box64|wine]\n' "$0" >&2
    exit 1
    ;;
esac
