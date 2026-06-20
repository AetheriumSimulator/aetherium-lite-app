#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_SRC_DIR="${ROOT_DIR}/build/proton-runtime/proton-redist-x86_64/dist"
SRC_DIR="${PROTON_REDIST_DIR:-${DEFAULT_SRC_DIR}}"
DST_DIR="${ROOT_DIR}/proton/src/main/resources/rawfile/runtime/proton"
WINE_HMOS_BUILD_DIR="${ROOT_DIR}/build/proton-runtime/wine-hmos-guest"
WINE_HMOS_LOADER="${WINE_HMOS_BUILD_DIR}/wine-hmos-loader.so"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "[proton-redist] missing Proton dist directory: ${SRC_DIR}" >&2
  echo "[proton-redist] run scripts/proton-runtime/build_proton_redist.sh first" >&2
  exit 1
fi

rm -rf "${DST_DIR}"
mkdir -p "${DST_DIR}"
# HarmonyOS rawfile packaging is driven by Windows-side Hvigor in the common
# DevEco setup, and it cannot reliably stat WSL symlinks. Materialize Proton's
# symlink-heavy redist tree into regular files before it becomes HSP payload.
cp -aL "${SRC_DIR}/." "${DST_DIR}/"

WINE_UNIX_DIR="${DST_DIR}/files/lib/wine/x86_64-unix"
mkdir -p "${WINE_UNIX_DIR}"
if [[ ! -f "${WINE_HMOS_LOADER}" ]]; then
  "${ROOT_DIR}/scripts/proton-runtime/build_wine_hmos_guest_shims.sh"
fi
cp -f "${WINE_HMOS_LOADER}" "${WINE_UNIX_DIR}/wine-hmos-loader.so"
"${ROOT_DIR}/scripts/proton-runtime/patch_ntdll_skip_wineboot.sh" "${WINE_UNIX_DIR}/ntdll.so"
"${ROOT_DIR}/scripts/proton-runtime/patch_ntdll_hmos_sigsys.sh" "${WINE_UNIX_DIR}/ntdll.so"
"${ROOT_DIR}/scripts/proton-runtime/patch_win32u_skip_builtin_callback.sh" \
  "${WINE_UNIX_DIR}/win32u.so"
"${ROOT_DIR}/scripts/proton-runtime/patch_user32_skip_uxtheme.sh" \
  "${DST_DIR}/files/lib/wine/x86_64-windows/user32.dll"
"${ROOT_DIR}/scripts/proton-runtime/patch_user32_skip_uxtheme.sh" \
  "${DST_DIR}/files/share/default_pfx/drive_c/windows/system32/user32.dll"

# HarmonyOS loads Proton through HSP native libraries and Box64 in-process
# dispatch. Do not package Unix process launchers as fake shared objects.
rm -f \
  "${DST_DIR}/files/bin/msidb" \
  "${DST_DIR}/files/bin/wine" \
  "${DST_DIR}/files/bin/wine64" \
  "${DST_DIR}/files/bin/wineserver" \
  "${WINE_UNIX_DIR}/wineserver-hmos.so"
find "${DST_DIR}/files/lib/wine" -type f \( \
  -name wine -o \
  -name wine64 -o \
  -name wine-preloader -o \
  -name wine64-preloader \
\) -delete

USER_REG="${DST_DIR}/files/share/default_pfx/user.reg"
if [[ -f "${USER_REG}" ]] && ! grep -q '^\[Software\\\\Wine\]' "${USER_REG}"; then
  cat >>"${USER_REG}" <<'EOF'

[Software\\Wine] 1780345012
#time=1dcf20395a1c4f8
"Version"="win11"
EOF
fi
"${ROOT_DIR}/scripts/proton-runtime/generate_rawfile_indexes.sh"
echo "[proton-redist] installed payload: ${DST_DIR}"
