#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECIPE_URL="${AETHERIUM_RUNTIME_RECIPE_URL:-https://github.com/caidingding233/aetherium-lite-runtime-using-wine-version-not-the-qemu-emulator-version.git}"
RECIPE_REF="${AETHERIUM_RUNTIME_RECIPE_REF:-main}"
RECIPE_DIR="${AETHERIUM_RUNTIME_RECIPE_DIR:-${ROOT_DIR}/.tmp/proton-runtime-recipe}"
PRINT_PATH=0
if [[ "${1:-}" == "--print-path" ]]; then
  PRINT_PATH=1
fi

run_git() {
  if [[ "${PRINT_PATH}" == "1" ]]; then
    git "$@" >&2
  else
    git "$@"
  fi
}

mkdir -p "$(dirname "${RECIPE_DIR}")"

if [[ ! -d "${RECIPE_DIR}/.git" ]]; then
  run_git clone "${RECIPE_URL}" "${RECIPE_DIR}"
else
  run_git -C "${RECIPE_DIR}" remote set-url origin "${RECIPE_URL}"
  run_git -C "${RECIPE_DIR}" fetch origin "${RECIPE_REF}"
fi

run_git -C "${RECIPE_DIR}" checkout "${RECIPE_REF}"
run_git -C "${RECIPE_DIR}" pull --ff-only origin "${RECIPE_REF}"

if [[ "${PRINT_PATH}" == "1" ]]; then
  printf '%s\n' "${RECIPE_DIR}"
else
  printf '[proton-runtime] runtime recipe synced: %s\n' "${RECIPE_DIR}"
fi
