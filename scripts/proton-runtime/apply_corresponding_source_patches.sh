#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${ROOT_DIR}/third_party/proton-runtime/src"
DEFAULT_RECIPE_DIR="${ROOT_DIR}/.tmp/proton-runtime-recipe"
PATCH_DIR="${PROTON_RUNTIME_SOURCE_PATCH_DIR:-${ROOT_DIR}/third_party/proton-runtime/source-patches}"

if [[ ! -d "${PATCH_DIR}" && -d "${DEFAULT_RECIPE_DIR}/third_party/proton-runtime/source-patches" ]]; then
  PATCH_DIR="${DEFAULT_RECIPE_DIR}/third_party/proton-runtime/source-patches"
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

printf '[proton-runtime] source patch dir: %s\n' "${PATCH_DIR}"
apply_component_patch box64 0001-hmos-local-working-tree.patch
apply_component_patch wine 0001-hmos-local-working-tree.patch
