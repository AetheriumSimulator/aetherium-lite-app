#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts/proton-runtime"
SRC_DIR="${ROOT_DIR}/third_party/proton-runtime/src"
DEFAULT_RECIPE_DIR="${ROOT_DIR}/.tmp/proton-runtime-recipe"
PATCH_DIR="${PROTON_RUNTIME_SOURCE_PATCH_DIR:-${ROOT_DIR}/third_party/proton-runtime/source-patches}"

if [[ ! -d "${PATCH_DIR}" && -d "${DEFAULT_RECIPE_DIR}/third_party/proton-runtime/source-patches" ]]; then
  PATCH_DIR="${DEFAULT_RECIPE_DIR}/third_party/proton-runtime/source-patches"
fi

if [[ ! -d "${PATCH_DIR}" && -x "${SCRIPT_DIR}/sync_runtime_recipe.sh" ]]; then
  recipe_dir="$("${SCRIPT_DIR}/sync_runtime_recipe.sh" --print-path)"
  if [[ -d "${recipe_dir}/third_party/proton-runtime/source-patches" ]]; then
    PATCH_DIR="${recipe_dir}/third_party/proton-runtime/source-patches"
  fi
fi

apply_component_patch() {
  local component="$1"
  local patch="$2"
  local repo_dir="${SRC_DIR}/${component}"
  local patch_path="${PATCH_DIR}/${component}/${patch}"

  if [[ ! -d "${repo_dir}/.git" ]]; then
    printf '[proton-runtime] missing source checkout: %s\n' "${repo_dir}" >&2
    exit 1
  fi
  if [[ ! -f "${patch_path}" ]]; then
    printf '[proton-runtime] missing corresponding-source patch: %s\n' "${patch_path}" >&2
    printf '[proton-runtime] run scripts/proton-runtime/sync_runtime_recipe.sh first, or set PROTON_RUNTIME_SOURCE_PATCH_DIR.\n' >&2
    exit 1
  fi

  if git -C "${repo_dir}" apply --reverse --check "${patch_path}" >/dev/null 2>&1; then
    printf '[proton-runtime] patch already applied: %s/%s\n' "${component}" "${patch}"
    return
  fi

  git -C "${repo_dir}" apply "${patch_path}"
  printf '[proton-runtime] patch applied: %s/%s\n' "${component}" "${patch}"
}

component_already_applied() {
  local component="$1"
  local repo_dir="${SRC_DIR}/${component}"

  case "${component}" in
    box64)
      [[ -f "${repo_dir}/src/hmos_inprocess.c" ]] &&
        grep -q 'box64_hmos_core' "${repo_dir}/CMakeLists.txt" &&
        grep -q 'box64_hmos_inprocess_mode' "${repo_dir}/src/wrapped/wrappedlibc.c"
      ;;
    wine)
      grep -q 'WINE_HMOS_PROCESS_BROKER_DIR' "${repo_dir}/dlls/ntdll/unix/process.c" &&
        grep -q 'WINE_HMOS_RUNTIME_ROOT' "${repo_dir}/server/unicode.c"
      ;;
    *)
      return 1
      ;;
  esac
}

apply_component() {
  local component="$1"

  if component_already_applied "${component}"; then
    printf '[proton-runtime] corresponding-source patch already applied: %s\n' "${component}"
    return
  fi

  case "${component}" in
    box64)
      apply_component_patch box64 0001-hmos-local-working-tree.patch
      ;;
    wine)
      apply_component_patch wine 0001-hmos-local-working-tree.patch
      ;;
    *)
      printf '[proton-runtime] unknown corresponding-source component: %s\n' "${component}" >&2
      exit 1
      ;;
  esac
}

printf '[proton-runtime] source patch dir: %s\n' "${PATCH_DIR}"
if [[ "$#" -gt 0 ]]; then
  for component in "$@"; do
    apply_component "${component}"
  done
else
  apply_component box64
  apply_component wine
fi
