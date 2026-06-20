# Proton Runtime Vendor Area

This directory is for the real Proton runtime source tree and HarmonyOS adaptation patches.

- `manifest.json` records the upstream repositories and output shared libraries expected by `Proton.hsp`.
- `src/` is intentionally ignored except for `.gitkeep`; run `scripts/proton-runtime/fetch_sources.sh` to fill it.
- `patches/` is where HarmonyOS-specific build and platform patches should be kept before they are applied to local source checkouts.

The app/game payload still lives in `entry/src/main/resources/rawfile/`. This directory is only for Box64, Wine/Proton, DXVK, vkd3d-proton, and bridge code.
