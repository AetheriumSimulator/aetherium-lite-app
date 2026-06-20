#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCH_DIR="${ROOT_DIR}/third_party/proton-runtime/patches"

apply_patch_if_needed() {
  local repo="$1"
  local patch="$2"
  local repo_dir="${ROOT_DIR}/third_party/proton-runtime/src/${repo}"

  if [[ ! -d "${repo_dir}/.git" ]]; then
    printf '[proton-runtime] missing repo for patch: %s\n' "${repo}" >&2
    exit 1
  fi

  if git -C "${repo_dir}" apply --reverse --check "${PATCH_DIR}/${patch}" >/dev/null 2>&1; then
    printf '[proton-runtime] patch already applied: %s/%s\n' "${repo}" "${patch}"
    return
  fi

  case "${patch}" in
    box64-hmos-fts-compat-header.patch)
      if [[ -f "${repo_dir}/src/include/fts.h" ]]; then
        printf '[proton-runtime] patch already applied: %s/%s\n' "${repo}" "${patch}"
        return
      fi
      ;;
    box64-hmos-libc-compat-header.patch)
      if [[ -f "${repo_dir}/src/include/hmos_compat.h" ]]; then
        printf '[proton-runtime] patch already applied: %s/%s\n' "${repo}" "${patch}"
        return
      fi
      ;;
    box64-hmos-error-header.patch)
      if [[ -f "${repo_dir}/src/include/error.h" ]]; then
        printf '[proton-runtime] patch already applied: %s/%s\n' "${repo}" "${patch}"
        return
      fi
      ;;
    box64-hmos-libc64-alias-compat.patch)
      if grep -q '#define fstat64 fstat' "${repo_dir}/src/wrapped/wrappedlibc.c"; then
        printf '[proton-runtime] patch already applied: %s/%s\n' "${repo}" "${patch}"
        return
      fi
      ;;
    box64-hmos-link-compat.patch)
      if grep -q 'box64_hmos_scandirat' "${repo_dir}/src/wrapped/wrappedlibc.c"; then
        printf '[proton-runtime] patch already applied: %s/%s\n' "${repo}" "${patch}"
        return
      fi
      ;;
  esac

  git -C "${repo_dir}" apply "${PATCH_DIR}/${patch}"
  printf '[proton-runtime] patch applied: %s/%s\n' "${repo}" "${patch}"
}

apply_patch_if_needed box64 box64-hmos-signal-nsig-words.patch
apply_patch_if_needed box64 box64-hmos-fts-compat-header.patch
apply_patch_if_needed box64 box64-hmos-libc-compat-header.patch
apply_patch_if_needed box64 box64-hmos-error-header.patch
apply_patch_if_needed box64 box64-hmos-pthread-compat.patch
apply_patch_if_needed box64 box64-hmos-shm-compat.patch
apply_patch_if_needed box64 box64-hmos-libc64-alias-compat.patch
apply_patch_if_needed box64 box64-hmos-link-compat.patch
