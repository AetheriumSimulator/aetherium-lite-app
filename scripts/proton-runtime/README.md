# Proton.Hsp Runtime Payload

This project keeps game payloads in `entry` rawfiles, but the compatibility layer belongs in `Proton.hsp`.

The HSP loads the runtime payload dynamically:

- `libproton_hmos_runtime.so` exports `proton_hmos_launch(const char *launch_request)`.
- `libbox64_hmos.so` is the HarmonyOS adapter that enters Box64 in-process.
- `libbox64_hmos_core.so` is the real arm64 Box64 shared-object payload packaged with `Proton.hsp`.
- `resources/rawfile/runtime/proton/` is the materialized Valve Proton redist payload, including Wine, DXVK, vkd3d-proton, vkd3d, lsteamclient, vrclient, and the default prefix template.

Run `scripts/proton-runtime/fetch_sources.sh` to place upstream sources under `third_party/proton-runtime/src/`.
If WSL needs the Windows host proxy, pass it explicitly:

```bash
PROTON_RUNTIME_PROXY=http://172.21.16.1:7897 scripts/proton-runtime/fetch_sources.sh
```

Or let the helper detect the WSL default gateway and use port `7897`:

```bash
scripts/proton-runtime/fetch_sources_host_proxy.sh
```

The default fetch skips submodules so the core source checkouts complete first. For a full Proton dependency tree:

```bash
PROTON_RUNTIME_PROXY=http://172.21.16.1:7897 PROTON_RUNTIME_FETCH_SUBMODULES=1 scripts/proton-runtime/fetch_sources.sh
```

Build and install the current Box64 in-process payload:

```bash
scripts/proton-runtime/apply_hmos_patches.sh
scripts/proton-runtime/configure_box64_hmos.sh
scripts/proton-runtime/build_box64_hmos.sh
scripts/proton-runtime/install_box64_payload.sh
```

Valve Proton itself is built inside the Proton SDK container. Configure and build a redist payload when Docker or Podman is available:

```bash
scripts/proton-runtime/configure_proton_redist.sh
scripts/proton-runtime/build_proton_redist.sh
scripts/proton-runtime/install_proton_redist_payload.sh
```

`install_proton_redist_payload.sh` copies the generated Proton redist into `proton/src/main/resources/rawfile/runtime/proton/` and materializes symlinks so Windows-side Hvigor can package the payload.

Build the tiny Win32 smoke-test executable and place it in the sample app rawfile:

```bash
scripts/proton-runtime/build_win32_smoke.sh
```

The sample app stages `runtime/proton` and `win32-smoke`, then launches `ProtonSmokeWin32.exe` through in-process Box64 into Wine. Prefix creation pins Wine's compatibility target to `win11`.
