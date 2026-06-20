#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT_DIR}/third_party/proton-runtime/hmos/wine_hmos_loader.c"
BUILD_DIR="${ROOT_DIR}/build/proton-runtime/wine-hmos-guest"
OUT="${BUILD_DIR}/wine-hmos-loader.so"
CC_BIN="${WINE_HMOS_GUEST_CC:-gcc}"

if [[ ! -f "${SRC}" ]]; then
  echo "[wine-hmos] missing source: ${SRC}" >&2
  exit 1
fi

mkdir -p "${BUILD_DIR}"
"${CC_BIN}" -shared -fPIC -O2 -Wall -Wextra -o "${OUT}" "${SRC}" -ldl

file "${OUT}"
SYMS="${BUILD_DIR}/wine-hmos-loader.symbols"
readelf -Ws "${OUT}" >"${SYMS}"
grep -q ' wine_hmos_main$' "${SYMS}"
echo "[wine-hmos] built guest loader SO: ${OUT}"
