#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INDEX_NAME="proton_rawfile_index.json"

generate_index() {
  local raw_root="$1"
  if [[ ! -d "${raw_root}" ]]; then
    return 0
  fi

  python3 - "${raw_root}" "${INDEX_NAME}" <<'PY'
import json
import os
import sys

raw_root = os.path.abspath(sys.argv[1])
index_name = sys.argv[2]
skip_names = {index_name, ".proton-rawfile-index.json", ".gitkeep", "PROTON_PLACEHOLDER.txt"}
skip_prefixes = (
    "files/share/wine/mono/",
    "files/share/wine/gecko/",
)
files = []

for current, dirs, names in os.walk(raw_root):
    dirs.sort()
    names.sort()
    for name in names:
        if name in skip_names:
            continue
        if name.startswith("."):
            continue
        path = os.path.join(current, name)
        rel = os.path.relpath(path, raw_root).replace(os.sep, "/")
        if any(rel.startswith(prefix) for prefix in skip_prefixes):
            continue
        files.append({"path": rel, "size": os.path.getsize(path)})

index_path = os.path.join(raw_root, index_name)
with open(index_path, "w", encoding="utf-8") as handle:
    json.dump({"version": 1, "files": files}, handle, ensure_ascii=True, separators=(",", ":"))
    handle.write("\n")

print(f"[rawfile-index] {index_path}: {len(files)} files")
PY
}

generate_index "${ROOT_DIR}/proton/src/main/resources/rawfile/runtime/proton"
generate_index "${ROOT_DIR}/entry/src/main/resources/rawfile/win32-smoke"
generate_index "${ROOT_DIR}/entry/src/main/resources/rawfile/mihoyo-launcher"
generate_index "${ROOT_DIR}/entry/src/main/resources/rawfile/genshin-impact-game"
