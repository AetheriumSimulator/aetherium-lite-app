# Aetherium Lite App

Aetherium Lite is a HarmonyOS shell for experimenting with a native Wine/Proton runtime on large-screen HarmonyOS devices.

This repository contains the app shell, ArkTS UI/session broker code, HarmonyOS native bridge code, runtime build scripts, and small smoke-test sources. The generated Proton/Wine runtime payload is intentionally not committed.

## Repository Layout

- `entry/`: HarmonyOS entry HAP and Wine desktop/window abilities.
- `proton/`: HarmonyOS shared HSP source for the Wine/Proton bridge.
- `scripts/proton-runtime/`: helper scripts for fetching, patching, building, and staging runtime payloads.
- `third_party/proton-runtime/`: manifest and HarmonyOS patch area for upstream runtime sources.
- `tools/win32-smoke/`: tiny Win32 smoke-test source code.

## Runtime Payload

The following generated artifacts are local build products and are not part of this MIT-licensed app source repository:

- `proton/src/main/resources/rawfile/runtime/proton/`
- `proton/src/main/libs/arm64-v8a/libbox64_hmos_core.so`
- `entry/src/main/cpp/*_patch_blob.inc`
- `entry/src/main/resources/rawfile/win32-smoke/*.exe`
- `entry/src/main/resources/rawfile/win32-smoke/*.dll`
- generated `.hap`, `.hsp`, `.app`, and `.har` files

Run the scripts under `scripts/proton-runtime/` to recreate the local runtime payload from upstream sources.

For the full runtime model, source checkout flow, and repository split, see `docs/RUNTIME_ARCHITECTURE_AND_SOURCE_GUIDE.md`.
The Wine/Proton runtime recipe lives in https://github.com/caidingding233/aetherium-lite-runtime-using-wine-version-not-the-qemu-emulator-version.

## Licensing

The original Aetherium Lite app and bridge source in this repository is licensed under MIT. Third-party runtime components keep their own licenses. See `THIRD_PARTY_NOTICES.md` and `docs/OPEN_SOURCE.md` before publishing binaries or runtime builds.

Game assets, commercial installers, account files, and proprietary launcher payloads are not included. Users must provide their own legally obtained Windows programs.

## Signing

Public source does not include HarmonyOS signing certificates, profiles, keystores, or passwords. Configure signing locally in DevEco Studio or with your own CI secrets.
