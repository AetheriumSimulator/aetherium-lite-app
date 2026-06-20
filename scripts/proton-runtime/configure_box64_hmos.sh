#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SDK_ROOT="${HARMONYOS_SDK_ROOT:-/mnt/c/Program Files/Huawei/DevEco Studio/sdk/default}"
OHOS_NATIVE="${SDK_ROOT}/openharmony/native"
HMOS_NATIVE="${SDK_ROOT}/hms/native"
CMAKE_EXE="${OHOS_NATIVE}/build-tools/cmake/bin/cmake.exe"
NINJA_EXE="${OHOS_NATIVE}/build-tools/cmake/bin/ninja.exe"
BOX64_SRC="${ROOT_DIR}/third_party/proton-runtime/src/box64"
BUILD_DIR="${ROOT_DIR}/build/proton-runtime/box64-hmos-arm64"
INSTALL_DIR="${ROOT_DIR}/proton/src/main/libs/arm64-v8a"

if [[ ! -x "${CMAKE_EXE}" ]]; then
  printf '[box64-hmos] missing cmake: %s\n' "${CMAKE_EXE}" >&2
  exit 1
fi

if [[ ! -d "${BOX64_SRC}/src" ]]; then
  printf '[box64-hmos] missing Box64 source: %s\n' "${BOX64_SRC}" >&2
  exit 1
fi

"${ROOT_DIR}/scripts/proton-runtime/apply_hmos_patches.sh"

mkdir -p "${BUILD_DIR}" "${INSTALL_DIR}"

cmake_path() {
  wslpath -m "$1"
}

"${CMAKE_EXE}" \
  -G Ninja \
  -S "$(cmake_path "${BOX64_SRC}")" \
  -B "$(cmake_path "${BUILD_DIR}")" \
  -DCMAKE_MAKE_PROGRAM="$(cmake_path "${NINJA_EXE}")" \
  -DCMAKE_TOOLCHAIN_FILE="$(cmake_path "${HMOS_NATIVE}/build/cmake/hmos.toolchain.cmake")" \
  -DOHOS_SDK_NATIVE="$(cmake_path "${OHOS_NATIVE}")" \
  -DHMOS_SDK_NATIVE="$(cmake_path "${HMOS_NATIVE}")" \
  -DOHOS_ARCH=arm64-v8a \
  -DOHOS_PLATFORM_LEVEL=23 \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_C_FLAGS="-include $(cmake_path "${BOX64_SRC}/src/include/hmos_compat.h")" \
  -DCMAKE_INSTALL_PREFIX="$(cmake_path "${INSTALL_DIR}")" \
  -DBOX64_HMOS_INPROCESS=ON \
  -DARM64=ON \
  -DANDROID=ON \
  -DHAVE_TRACE=OFF \
  -DNOLOADADDR=ON \
  -DNO_LIB_INSTALL=ON \
  -DNO_CONF_INSTALL=ON \
  -DNOGIT=ON \
  -DBOX32=OFF

printf '[box64-hmos] configured: %s\n' "${BUILD_DIR}"
