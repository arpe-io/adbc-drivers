#!/bin/sh
# Checks the LIVE releases, without downloading any driver binary: for every
# driver in registry.json, the latest version install.sh resolves must be a
# release that carries both binaries, and its SHA256SUMS must list each of them
# with the SHA-256 that GitHub itself computed for the uploaded file.
#
#   sh tests/check_releases.sh
#
# Needs network access, plus `gh` (authenticated, e.g. GH_TOKEN) and `jq`. Only
# SHA256SUMS is downloaded, so this does not add to the binaries' download counts.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=$(jq -r .dist_repo "$ROOT/registry.json")
WORK=$(mktemp -d "${TMPDIR:-/tmp}/arpeio-adbc-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
FAILED=0
bad() { FAILED=$((FAILED + 1)); printf 'FAIL - %s\n' "$*"; }

sh "$ROOT/install.sh" --list > "$WORK/list" 2>&1 \
  || { cat "$WORK/list"; echo "install.sh --list failed"; exit 1; }

for d in $(jq -r '.drivers | keys_unsorted[]' "$ROOT/registry.json"); do
  lib=$(jq -r --arg d "$d" '.drivers[$d].lib' "$ROOT/registry.json")
  # The version is the first version-looking field of the driver's line (an
  # "installed ..." note may follow it on a machine that has the driver).
  ver=$(awk -v d="$d" '$1 == d { for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+/) { print $i; exit } }' "$WORK/list")
  if [ -z "$ver" ]; then bad "$d: install.sh --list resolves no published version"; continue; fi
  tag="$d-v$ver"

  # "<sha256> <name>" for every asset, with the digest GitHub computed on upload.
  gh api "repos/$REPO/releases/tags/$tag" \
    --jq '.assets[] | "\(.digest // "" | sub("^sha256:"; "")) \(.name)"' > "$WORK/assets" \
    || { bad "$d: no release $tag"; continue; }
  if ! curl -fsSL -o "$WORK/sums" "https://github.com/$REPO/releases/download/$tag/SHA256SUMS"; then
    bad "$tag: SHA256SUMS cannot be downloaded"; continue
  fi

  ok=1
  for asset in "lib${lib}-linux-x64.so" "${lib}-win-x64.dll"; do
    actual=$(awk -v a="$asset" '$2 == a { print $1 }' "$WORK/assets")
    listed=$(awk -v a="$asset" '$2 == a { print $1 }' "$WORK/sums")
    if [ -z "$actual" ]; then bad "$tag: asset $asset is missing"; ok=0
    elif [ -z "$listed" ]; then bad "$tag: SHA256SUMS has no entry for $asset"; ok=0
    elif [ "$actual" != "$listed" ]; then bad "$tag: SHA256SUMS does not match $asset"; ok=0
    fi
  done
  if [ "$ok" = 1 ]; then printf 'ok   - %s: both binaries present, SHA256SUMS matches\n' "$tag"; fi
done

printf '\n'
if [ "$FAILED" != 0 ]; then printf '%s problem(s) found\n' "$FAILED"; exit 1; fi
printf 'latest releases are consistent\n'
