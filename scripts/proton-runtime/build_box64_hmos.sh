#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SDK_ROOT="${HARMONYOS_SDK_ROOT:-/mnt/c/Program Files/Huawei/DevEco Studio/sdk/default}"
OHOS_NATIVE="${SDK_ROOT}/openharmony/native"
CMAKE_EXE="${OHOS_NATIVE}/build-tools/cmake/bin/cmake.exe"
BUILD_DIR="${ROOT_DIR}/build/proton-runtime/box64-hmos-arm64"

if [[ ! -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
  "${ROOT_DIR}/scripts/proton-runtime/configure_box64_hmos.sh"
fi

"${CMAKE_EXE}" --build "$(wslpath -m "${BUILD_DIR}")" --target box64_hmos_core --parallel "${BOX64_BUILD_JOBS:-4}"

printf '[box64-hmos] built target box64_hmos_core in %s\n' "${BUILD_DIR}"
