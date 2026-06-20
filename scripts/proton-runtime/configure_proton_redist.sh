#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${ROOT_DIR}/third_party/proton-runtime/src/proton"
BUILD_DIR="${ROOT_DIR}/build/proton-runtime/proton-redist-x86_64"
BUILD_NAME="${PROTON_HMOS_BUILD_NAME:-proton-hmos}"
TARGET_ARCH="${PROTON_HMOS_TARGET_ARCH:-x86_64}"

if [[ ! -x "${SRC_DIR}/configure.sh" ]]; then
  echo "[proton-redist] missing Proton source: ${SRC_DIR}" >&2
  echo "[proton-redist] run scripts/proton-runtime/fetch_sources_host_proxy.sh first" >&2
  exit 1
fi

ENGINE="${PROTON_CONTAINER_ENGINE:-}"
if [[ -z "${ENGINE}" ]]; then
  engine_works() {
    local candidate="$1"
    command -v "${candidate}" >/dev/null 2>&1 && "${candidate}" info >/dev/null 2>&1
  }

  if engine_works podman; then
    ENGINE="podman"
  elif engine_works docker; then
    ENGINE="docker"
  elif [[ -x "/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe" ]]; then
    ENGINE="${ROOT_DIR}/scripts/proton-runtime/docker-desktop-wsl.sh"
  else
    echo "[proton-redist] Docker/Podman is required by Valve Proton's build system." >&2
    echo "[proton-redist] Install one of them or set PROTON_CONTAINER_ENGINE to a compatible engine." >&2
    exit 2
  fi
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
"${SRC_DIR}/configure.sh" \
  --build-name="${BUILD_NAME}" \
  --target-arch="${TARGET_ARCH}" \
  --container-engine="${ENGINE}" \
  "$@"

echo "[proton-redist] configured build dir: ${BUILD_DIR}"
