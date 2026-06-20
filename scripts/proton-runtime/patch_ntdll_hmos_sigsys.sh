#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NTDLL="${1:-${ROOT_DIR}/proton/src/main/resources/rawfile/runtime/proton/files/lib/wine/x86_64-unix/ntdll.so}"

python3 - "$NTDLL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())

patches = [
    # Low native syscall-address check: route to the existing sigaction(SIGSYS)
    # block instead of returning before the handler is registered.
    (0x5044F, bytes.fromhex("73 09"), bytes.fromhex("73 3f"), "low sc_seccomp branch"),
    (0x50458, bytes.fromhex("72 36"), bytes.fromhex("eb 36"), "low libc syscall branch"),
    # After sigaction(SIGSYS), return immediately. HarmonyOS in-process uses
    # Box64 to synthesize SIGSYS, so installing seccomp/BPF is both unnecessary
    # and unsafe when native libraries live below Wine's native-address cutoff.
    (0x504C2, bytes.fromhex("45 31 c9 b9 22"), bytes.fromhex("e9 a0 ff ff ff"), "return after sigaction"),
]

changed = False
for offset, expected, replacement, name in patches:
    current = bytes(data[offset:offset + len(expected)])
    if current == replacement:
        print(f"[proton-runtime] ntdll HMOS SIGSYS already patched: {name}")
        continue
    if current != expected:
        raise SystemExit(
            f"[proton-runtime] refusing to patch unexpected ntdll bytes for {name} "
            f"at 0x{offset:x}: {current.hex(' ')}"
        )
    data[offset:offset + len(replacement)] = replacement
    changed = True
    print(f"[proton-runtime] patched ntdll HMOS SIGSYS: {name}")

if changed:
    path.write_bytes(data)
PY
