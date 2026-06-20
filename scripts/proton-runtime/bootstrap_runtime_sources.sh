#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts/proton-runtime"

recipe_dir="$("${SCRIPT_DIR}/sync_runtime_recipe.sh" --print-path)"

PROTON_RUNTIME_MANIFEST="${recipe_dir}/third_party/proton-runtime/manifest.json" \
  "${SCRIPT_DIR}/fetch_sources.sh"

PROTON_RUNTIME_SOURCE_PATCH_DIR="${recipe_dir}/third_party/proton-runtime/source-patches" \
  "${SCRIPT_DIR}/apply_corresponding_source_patches.sh"

PROTON_RUNTIME_LICENSE_DIR="${recipe_dir}/LICENSES" \
  "${SCRIPT_DIR}/audit_licenses.sh"

printf '[proton-runtime] bootstrap complete. Next: configure/build the runtime, then assemble Proton.hsp and entry HAP.\n'
