#!/usr/bin/env bash
set -euo pipefail

DOCKER_EXE="${DOCKER_DESKTOP_EXE:-/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe}"
DOCKER_BIN_DIR="$(dirname "${DOCKER_EXE}")"

if [[ ! -x "${DOCKER_EXE}" ]]; then
  echo "[docker-desktop-wsl] docker.exe not found: ${DOCKER_EXE}" >&2
  exit 127
fi

export PATH="${DOCKER_BIN_DIR}:${PATH}"
DOCKER_CONFIG_LINUX="${DOCKER_CONFIG:-${HOME}/.config/proton-hmos-docker}"
mkdir -p "${DOCKER_CONFIG_LINUX}"
if [[ ! -f "${DOCKER_CONFIG_LINUX}/config.json" ]]; then
  printf '{}\n' > "${DOCKER_CONFIG_LINUX}/config.json"
fi
export DOCKER_CONFIG="$(wslpath -w "${DOCKER_CONFIG_LINUX}")"

translate_volume() {
  local spec="$1"
  local host="${spec%%:*}"
  local rest="${spec#*:}"

  if [[ "${host}" == "${spec}" || "${host}" != /* ]]; then
    printf '%s\n' "${spec}"
    return
  fi

  printf '%s:%s\n' "$(wslpath -w "${host}")" "${rest}"
}

translated=()
while (($# > 0)); do
  case "$1" in
    -v|--volume)
      translated+=("$1")
      shift
      if (($# > 0)); then
        translated+=("$(translate_volume "$1")")
        shift
      fi
      ;;
    --volume=*)
      translated+=("--volume=$(translate_volume "${1#--volume=}")")
      shift
      ;;
    *)
      translated+=("$1")
      shift
      ;;
  esac
done

exec "${DOCKER_EXE}" --config "${DOCKER_CONFIG}" "${translated[@]}"
