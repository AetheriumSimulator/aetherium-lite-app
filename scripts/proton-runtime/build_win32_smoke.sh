#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="${PROTON_SDK_IMAGE:-registry.gitlab.steamos.cloud/proton/steamrt4/sdk/x86_64:4.0.20260331.220802-0}"
ENGINE="${PROTON_CONTAINER_ENGINE:-${ROOT_DIR}/scripts/proton-runtime/docker-desktop-wsl.sh}"
SRC="${ROOT_DIR}/tools/win32-smoke/smoke_win32.c"
OUT_DIR="${ROOT_DIR}/entry/src/main/resources/rawfile/win32-smoke"
OUT="${OUT_DIR}/ProtonSmokeWin32.exe"
GAME_SRC="${ROOT_DIR}/tools/win32-smoke/tiny_game_win32.c"
GAME_OUT="${OUT_DIR}/ProtonTinyGame.exe"
D3D11_SRC="${ROOT_DIR}/tools/win32-smoke/d3d11_smoke.c"
D3D11_OUT="${OUT_DIR}/ProtonD3D11Smoke.exe"
UXTHEME_SRC="${ROOT_DIR}/tools/win32-smoke/uxtheme_stub.c"
UXTHEME_OUT="${OUT_DIR}/uxtheme.dll"

mkdir -p "${OUT_DIR}"

find_zig() {
  if [[ -n "${PROTON_ZIG:-}" && -x "${PROTON_ZIG}" ]]; then
    printf '%s\n' "${PROTON_ZIG}"
    return 0
  fi
  if command -v zig >/dev/null 2>&1; then
    command -v zig
    return 0
  fi
  local cached="/mnt/c/tmp/proton-hmos-tools/zig-x86_64-windows-0.16.0/zig.exe"
  if [[ -x "${cached}" ]]; then
    printf '%s\n' "${cached}"
    return 0
  fi
  return 1
}

if ZIG="$(find_zig)"; then
  zig_path() {
    if [[ "${ZIG}" == *.exe && "$(command -v wslpath || true)" != "" ]]; then
      wslpath -w "$1"
    else
      printf '%s\n' "$1"
    fi
  }

  "${ZIG}" cc -target x86_64-windows-gnu -municode -O2 "$(zig_path "${SRC}")" \
    -o "$(zig_path "${OUT}")" -luser32 -lgdi32 -ladvapi32 '-Wl,--subsystem,windows'
  "${ZIG}" cc -target x86_64-windows-gnu -municode -O2 "$(zig_path "${GAME_SRC}")" \
    -o "$(zig_path "${GAME_OUT}")" -luser32 -lgdi32 '-Wl,--subsystem,windows'
  "${ZIG}" cc -target x86_64-windows-gnu -municode -O2 "$(zig_path "${D3D11_SRC}")" \
    -o "$(zig_path "${D3D11_OUT}")" -luser32 -lgdi32 -ld3d11 -ldxgi '-Wl,--subsystem,windows'
  "${ZIG}" cc -target x86_64-windows-gnu -nostdlib -O2 "$(zig_path "${UXTHEME_SRC}")" \
    -shared -o "$(zig_path "${UXTHEME_OUT}")" '-Wl,--entry,DllMainCRTStartup' '-Wl,--subsystem,windows'
else
  "${ENGINE}" run --rm \
    -v "${ROOT_DIR}:/work" \
    -w /work \
    "${IMAGE}" \
    bash -lc 'set -euo pipefail
      x86_64-w64-mingw32-gcc -municode -mwindows -O2 tools/win32-smoke/smoke_win32.c -o entry/src/main/resources/rawfile/win32-smoke/ProtonSmokeWin32.exe -luser32 -lgdi32 -ladvapi32
      x86_64-w64-mingw32-gcc -municode -mwindows -O2 tools/win32-smoke/tiny_game_win32.c -o entry/src/main/resources/rawfile/win32-smoke/ProtonTinyGame.exe -luser32 -lgdi32
      x86_64-w64-mingw32-gcc -municode -mwindows -O2 tools/win32-smoke/d3d11_smoke.c -o entry/src/main/resources/rawfile/win32-smoke/ProtonD3D11Smoke.exe -luser32 -lgdi32 -ld3d11 -ldxgi
      x86_64-w64-mingw32-gcc -shared -nostdlib -O2 tools/win32-smoke/uxtheme_stub.c -o entry/src/main/resources/rawfile/win32-smoke/uxtheme.dll -Wl,--entry,DllMainCRTStartup -Wl,--subsystem,windows'
fi

rm -f "${OUT_DIR}"/*.pdb "${OUT_DIR}"/*.lib
"${ROOT_DIR}/scripts/proton-runtime/generate_rawfile_indexes.sh"
echo "[win32-smoke] built ${OUT}"
echo "[win32-smoke] built ${GAME_OUT}"
echo "[win32-smoke] built ${D3D11_OUT}"
echo "[win32-smoke] built ${UXTHEME_OUT}"
