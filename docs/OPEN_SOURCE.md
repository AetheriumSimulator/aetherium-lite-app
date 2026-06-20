# Open Source Plan

This project should be opened as multiple deliverables rather than one giant MIT repository.

## Recommended Repositories

1. `aetherium-lite-app`
   - License: MIT for original app and bridge source.
   - Contents: HarmonyOS App/HSP source, scripts, patch metadata, smoke-test source, documentation.
   - Excludes: generated Proton/Wine payloads, `.hap/.hsp`, Box64 `.so`, Wine-derived binary blobs, proprietary game assets, and signing materials.

2. `aetherium-wine-runtime`
   - License: mixed, matching upstream components.
   - Contents: runtime source manifests, exact Wine/Proton/Box64/DXVK/vkd3d-proton source refs, HarmonyOS patches, build scripts, corresponding source for released binaries.
   - Needed because Wine and vkd3d-proton are LGPL components.

3. Optional release/artifact channel
   - Use GitHub Releases or a separate artifact bucket for generated runtime packages.
   - Do not store multi-GB generated payloads in git history.

## Why Not Full MIT?

The App shell can be MIT. The runtime cannot be relicensed to MIT by this project because it includes upstream components with their own licenses.

Important examples:

- Wine is LGPL-2.1-or-later.
- vkd3d-proton is LGPL-2.1.
- Box64 is MIT.
- DXVK is zlib/libpng style.
- Proton distribution notices include many additional bundled licenses.

The current HarmonyOS design loads key runtime pieces as in-process shared objects. That is fine architecturally, but it makes LGPL compliance more important for binary releases: publish the corresponding source and patches for LGPL-covered runtime libraries, keep notices with the binaries, and document how developers can rebuild or replace those runtime pieces. See `RUNTIME_ARCHITECTURE_AND_SOURCE_GUIDE.md` for the practical source checkout flow.

## Before Publishing Binaries

- Generate a `NOTICE` bundle from the exact runtime payload being shipped.
- Publish corresponding source and patch refs for modified LGPL components.
- Document how a user can rebuild or replace LGPL-covered runtime libraries.
- Keep app signing profiles and keystores in local secrets only.
- Check every rawfile payload for proprietary assets before release.

## Current Source-Only Policy

The public app repository intentionally ignores:

- `proton/src/main/resources/rawfile/runtime/proton/`
- `proton/src/main/libs/arm64-v8a/*.so`
- `entry/src/main/cpp/*_patch_blob.inc`
- generated Win32 smoke-test binaries
- generated HarmonyOS packages
- screenshots and temporary logs

Local developers can regenerate those files with `scripts/proton-runtime/`.
