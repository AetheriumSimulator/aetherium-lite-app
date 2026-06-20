#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/proton-runtime/proton-redist-x86_64"

if [[ ! -f "${BUILD_DIR}/Makefile" ]]; then
  "${ROOT_DIR}/scripts/proton-runtime/configure_proton_redist.sh"
fi

make -C "${BUILD_DIR}" redist "$@"
echo "[proton-redist] built dist under: ${BUILD_DIR}/dist"
