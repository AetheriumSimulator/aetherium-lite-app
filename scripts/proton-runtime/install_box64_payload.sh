#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT_DIR}/build/proton-runtime/box64-hmos-arm64/libbox64_hmos_core.so"
DST_DIR="${ROOT_DIR}/proton/src/main/libs/arm64-v8a"
DST="${DST_DIR}/libbox64_hmos_core.so"

if [[ ! -f "${SRC}" ]]; then
  echo "[box64-hmos] missing in-process shared object: ${SRC}" >&2
  echo "[box64-hmos] run scripts/proton-runtime/build_box64_hmos.sh first" >&2
  exit 1
fi

mkdir -p "${DST_DIR}"
cp "${SRC}" "${DST}"
chmod 0644 "${DST}"
echo "[box64-hmos] installed payload: ${DST}"
