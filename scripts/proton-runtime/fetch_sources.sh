#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${ROOT_DIR}/third_party/proton-runtime/src"
MANIFEST="${PROTON_RUNTIME_MANIFEST:-${ROOT_DIR}/third_party/proton-runtime/manifest.json}"
PROXY_URL="${PROTON_RUNTIME_PROXY:-${HOST_PROXY:-}}"
FETCH_SUBMODULES="${PROTON_RUNTIME_FETCH_SUBMODULES:-0}"
PINNED="${PROTON_RUNTIME_PINNED:-1}"

GIT_ARGS=()
if [[ -n "${PROXY_URL}" ]]; then
  export http_proxy="${PROXY_URL}"
  export https_proxy="${PROXY_URL}"
  export HTTP_PROXY="${PROXY_URL}"
  export HTTPS_PROXY="${PROXY_URL}"
  GIT_ARGS=(-c "http.proxy=${PROXY_URL}" -c "https.proxy=${PROXY_URL}")
  printf '[proton-runtime] using proxy %s\n' "${PROXY_URL}"
fi

mkdir -p "${SRC_DIR}"

fetch_repo() {
  local name="$1"
  local url="$2"
  local ref="$3"
  local verified_head="$4"
  local dir="${SRC_DIR}/${name}"
  local fetch_target="${ref}"

  if [[ "${PINNED}" == "1" && -n "${verified_head}" ]]; then
    fetch_target="${verified_head}"
  fi

  printf '[proton-runtime] %s <- %s (%s)\n' "${name}" "${url}" "${fetch_target}"
  if [[ ! -d "${dir}/.git" ]]; then
    mkdir -p "${dir}"
    git "${GIT_ARGS[@]}" -C "${dir}" init
    git "${GIT_ARGS[@]}" -C "${dir}" remote add origin "${url}"
  else
    git "${GIT_ARGS[@]}" -C "${dir}" remote set-url origin "${url}"
  fi

  git "${GIT_ARGS[@]}" -C "${dir}" fetch --depth=1 --recurse-submodules=no origin "${fetch_target}"
  git "${GIT_ARGS[@]}" -c submodule.recurse=false -C "${dir}" checkout --detach FETCH_HEAD
  if [[ "${PINNED}" == "1" ]]; then
    local actual_head
    actual_head="$(git -C "${dir}" rev-parse HEAD)"
    if [[ "${actual_head}" != "${verified_head}" ]]; then
      printf '[proton-runtime] ERROR: %s resolved to %s, expected %s\n' \
        "${name}" "${actual_head}" "${verified_head}" >&2
      exit 1
    fi
  fi
  if [[ "${FETCH_SUBMODULES}" == "1" ]]; then
    git "${GIT_ARGS[@]}" -C "${dir}" submodule update --init --recursive --depth=1
  else
    printf '[proton-runtime] %s: submodules skipped; set PROTON_RUNTIME_FETCH_SUBMODULES=1 for full upstream dependency checkout\n' "${name}"
  fi
}

fetch_manifest() {
  if [[ -f "${MANIFEST}" ]] && command -v python3 >/dev/null 2>&1; then
    python3 - "${MANIFEST}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
for source in manifest.get("sources", []):
    print("\t".join([
        source.get("name", ""),
        source.get("url", ""),
        source.get("ref", ""),
        source.get("verifiedHead", ""),
    ]))
PY
    return
  fi

  cat <<'EOF'
proton	https://github.com/ValveSoftware/Proton.git	bleeding-edge	75fadb148aab81f3868224c5243beda68768eade
box64	https://github.com/ptitSeb/box64.git	main	3583d9c90e042694a5b0ac2511603ba8230c2316
wine	https://github.com/wine-mirror/wine.git	master	2cac6ccf33c0807f374dc96f5a20e35a2da86157
dxvk	https://github.com/doitsujin/dxvk.git	master	be4ac08faa1ba7546193995ac6e45ca8c07763d4
vkd3d-proton	https://github.com/HansKristian-Work/vkd3d-proton.git	master	110e8bd4ee09c40031f5513258a10df59d27fd94
EOF
}

if [[ -f "${MANIFEST}" ]]; then
  printf '[proton-runtime] manifest: %s\n' "${MANIFEST}"
else
  printf '[proton-runtime] manifest missing, using built-in source list: %s\n' "${MANIFEST}"
fi

while IFS=$'\t' read -r name url ref verified_head; do
  [[ -n "${name}" ]] || continue
  fetch_repo "${name}" "${url}" "${ref}" "${verified_head}"
done < <(fetch_manifest)

printf '[proton-runtime] source checkout complete: %s\n' "${SRC_DIR}"
