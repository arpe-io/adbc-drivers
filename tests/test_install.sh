#!/bin/sh
# Tests for install.sh — no network: the GitHub API (`fetch`) and the binary
# download (`download`) are replaced by shell functions.
#
#   sh tests/test_install.sh
#
# Each test runs in its own subshell that sources install.sh (the script's
# ARPEIO_ADBC_INSTALL_SOURCE hook loads the functions without running main).
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/arpeio-adbc-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
PASS=0
FAIL=0

# A release listing in the order the GitHub API returns it: 120 arpemssql
# releases first, then the only two arpeteradata ones — which therefore sit
# beyond the first page of 100.
FIXTURE="$WORK/tags.txt"
: > "$FIXTURE"
_i=120
while [ "$_i" -ge 1 ]; do
  printf '    "tag_name": "arpemssql-v0.9.%s",\n' "$_i" >> "$FIXTURE"
  _i=$((_i - 1))
done
printf '    "tag_name": "arpeteradata-v0.3.8",\n' >> "$FIXTURE"
printf '    "tag_name": "arpeteradata-v0.3.6",\n' >> "$FIXTURE"

# Mocks, written to a file so every test subshell can load the same ones.
# - fetch: serves the fixture 100 tags per page, honouring `page=N`; counts its
#   calls in $CALLS; fails on page $FAIL_PAGE when that is set.
# - download: fails unless DL_MODE=ok, so no test ever touches the network. With
#   DL_MODE=ok it writes a fake driver binary, and for SHA256SUMS a matching
#   checksum line — or none at all (SUMS_MODE=missing) or a wrong one (=bad).
# - uname: a Linux x64 machine, whatever the tests really run on.
# - system_manifest_dir: under the scratch dir, never the real /etc.
cat > "$WORK/mocks.sh" <<'EOF'
fetch() {
  printf 'x\n' >> "$CALLS"
  case "$1" in *"&page="*) _pg=${1##*&page=}; _pg=${_pg%%&*} ;; *) _pg=1 ;; esac
  if [ "${FAIL_PAGE:-0}" = "$_pg" ]; then return 22; fi
  awk -v p="$_pg" 'NR > (p - 1) * 100 && NR <= p * 100' "$FIXTURE"
}
download() {
  [ "${DL_MODE:-fail}" = ok ] || return 1
  case "$1" in
    */SHA256SUMS)
      case "${SUMS_MODE:-ok}" in
        missing) return 1 ;;
        bad) printf '%s  %s\n' 0000000000000000 "$LAST_ASSET" > "$2" ;;
        *)   printf '%s  %s\n' "$(sha256_of "$LAST_PATH")" "$LAST_ASSET" > "$2" ;;
      esac ;;
    *) printf 'driver binary from %s\n' "$1" > "$2"; LAST_PATH=$2; LAST_ASSET=${2##*/} ;;
  esac
}
uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac; }
system_manifest_dir() { printf '%s\n' "$SYSROOT/etc/adbc/drivers"; }
EOF

# run <name> <script>: run <script> in a fresh subshell with install.sh and the
# mocks loaded. Leaves stdout in $WORK/out, stderr in $WORK/err, status in $RC.
run() {
  : > "$WORK/calls"
  rm -rf "${WORK:?}/home" "${WORK:?}/sys"
  mkdir -p "$WORK/home"
  # The variables below are read by install.sh and the mocks, sourced at run time.
  # shellcheck disable=SC2034
  (
    CALLS="$WORK/calls"; FIXTURE=$FIXTURE; SYSROOT="$WORK/sys"
    ARPEIO_ADBC_INSTALL_SOURCE=1
    # shellcheck disable=SC1091
    . "$ROOT/install.sh"
    . "$WORK/mocks.sh"
    VERSION=latest; SCOPE=user; SCOPE_SET=0; PREFIX=""; DIR=""; DRIVER=""
    LICENSE=""; LICENSE_CONTENT=""; SKIP_CHECKSUM=0
    # Every install location is derived from these two; pin both so no test can
    # reach the real home or the real ADBC manifest directory.
    HOME="$WORK/home"; XDG_CONFIG_HOME="$WORK/home/.config"
    eval "$1"
  ) > "$WORK/out" 2> "$WORK/err"
  RC=$?
}
api_calls() { wc -l < "$WORK/calls" | tr -d ' '; }

ok()   { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n       %s\n' "$1" "$2"
         sed 's/^/       stderr: /' "$WORK/err"; }
# check <name> <condition...>: the test passes when the condition holds.
check() { _n=$1; shift; if "$@"; then ok "$_n"; else fail "$_n" "condition failed: $*"; fi; }
out_is()        { [ "$(cat "$WORK/out")" = "$1" ]; }
err_has()       { grep -q -- "$1" "$WORK/err"; }
err_lacks()     { ! grep -q -- "$1" "$WORK/err"; }
rc_is()         { [ "$RC" = "$1" ]; }
rc_nonzero()    { [ "$RC" != 0 ]; }
calls_are()     { [ "$(api_calls)" = "$1" ]; }
exists()        { [ -e "$1" ]; }
missing()       { [ ! -e "$1" ]; }
file_has()      { grep -q -- "$2" "$1"; }

# Where a default (user-scope) install of arpemssql lands in the scratch home.
LIBDIR="$WORK/home/.local/lib/arpeio-adbc/arpemssql"
LIB="$LIBDIR/libarpemssql_adbc_driver-linux-x64.so"
MANIFEST="$WORK/home/.config/adbc/drivers/arpemssql.toml"

# ---- pagination ---------------------------------------------------------------
run 'resolve_latest arpeteradata'
check "latest is found for a driver whose releases are all past the first 100" \
  out_is "arpeteradata-v0.3.8"

run 'resolve_versions arpemssql | wc -l | tr -d " "'
check "every version is listed when a driver's releases span two pages" out_is "120"

run 'resolve_latest arpemssql'
check "latest is the highest version across pages" out_is "arpemssql-v0.9.120"

run 'do_list'
check "--list reads the release listing once (2 pages), not once per driver" calls_are 2
check "--list shows the latest of a driver listed on page 2" err_has "arpeteradata .* 0\.3\.8"

# ---- API failure ---------------------------------------------------------------
run 'FAIL_PAGE=2; do_list'
check "--list fails when a page of the listing cannot be fetched" rc_nonzero
check "--list reports the API failure" err_has "GitHub API"
check "--list does not report a failed listing as 'not published yet'" err_lacks "not published yet"

run 'FAIL_PAGE=1; do_install arpemssql'
check "installing latest fails when the listing cannot be fetched" rc_nonzero
check "installing latest reports the API failure" err_has "GitHub API"
check "installing latest does not report a failed listing as 'no published release'" \
  err_lacks "no published release"

run 'FAIL_PAGE=1; do_download arpemssql'
check "--download-only of latest reports the API failure" err_has "GitHub API"

run 'FAIL_PAGE=1; do_versions'
check "--versions fails when the listing cannot be fetched" rc_nonzero

# A listing that never ends (a proxy or mirror ignoring `page=`) must stop with
# an error instead of looping forever.
run 'fetch() { printf "x\n" >> "$CALLS"; head -n 100 "$FIXTURE"; }; do_list'
check "an endless listing stops with an error" rc_nonzero
check "an endless listing is reported" err_has "GitHub API"

# ---- pinned version --------------------------------------------------------------
run 'VERSION=0.9.7; do_install arpemssql'
check "installing a pinned version makes no API call" calls_are 0
check "installing a pinned version goes straight to the download" err_has "arpemssql-v0.9.7"

# ---- architecture ------------------------------------------------------------------
UNAME_ARM='uname() { case "$1" in -s) echo Linux ;; -m) echo aarch64 ;; esac; }'
run "$UNAME_ARM; VERSION=0.9.7; do_install arpemssql"
check "arm64 is rejected" rc_nonzero
check "arm64 is rejected with a clear message" err_has "arm64 is not supported yet"
check "arm64 is rejected before any download is attempted" err_lacks "download failed"

run 'uname() { case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac; }; detect_platform; echo "$MANIFEST_KEY"'
check "x86_64 is still accepted" out_is "linux_amd64"

# ---- checksum verification --------------------------------------------------------
run 'DL_MODE=ok; VERSION=0.9.7; do_install arpemssql'
check "an install verifies the download against SHA256SUMS" err_has "checksum OK"
check "an install writes the library" exists "$LIB"
check "an install writes the manifest with the version" file_has "$MANIFEST" 'version = "0.9.7"'

run 'DL_MODE=ok; SUMS_MODE=bad; VERSION=0.9.7; do_install arpemssql'
check "a checksum mismatch stops the install" rc_nonzero
check "a checksum mismatch installs nothing" missing "$LIB"

run 'DL_MODE=ok; SUMS_MODE=missing; VERSION=0.9.7; do_install arpemssql'
check "an install fails when the release SHA256SUMS cannot be downloaded" rc_nonzero
check "a missing SHA256SUMS is named in the error" err_has "SHA256SUMS"
check "a missing SHA256SUMS error points at --skip-checksum" err_has "skip-checksum"
check "a missing SHA256SUMS installs nothing" missing "$LIB"
check "a missing SHA256SUMS writes no manifest" missing "$MANIFEST"

run 'DL_MODE=ok; SUMS_MODE=missing; SKIP_CHECKSUM=1; VERSION=0.9.7; do_install arpemssql'
check "--skip-checksum installs without SHA256SUMS" exists "$LIB"
check "--skip-checksum says the download was not verified" err_has "without checksum verification"

run 'DL_MODE=ok; SUMS_MODE=missing; VERSION=0.9.7; DIR="$HOME/bundle"; do_download arpemssql'
check "--download-only fails when the release SHA256SUMS cannot be downloaded" rc_nonzero
check "--download-only leaves no unverified binary behind" \
  missing "$WORK/home/bundle/libarpemssql_adbc_driver-linux-x64.so"

run 'DL_MODE=ok; SUMS_MODE=missing; SKIP_CHECKSUM=1; VERSION=0.9.7; DIR="$HOME/bundle"; do_download arpemssql'
check "--download-only --skip-checksum downloads without SHA256SUMS" \
  exists "$WORK/home/bundle/libarpemssql_adbc_driver-linux-x64.so"

# ---- GitHub token -------------------------------------------------------------------
# These exercise the real fetch/download (re-sourced over the mocks) with curl
# replaced by a function that records its arguments.
REAL='. "$ROOT/install.sh"; curl() { printf "%s\n" "$@" >> "$HOME/../curl_args"; }; : > "$HOME/../curl_args"'
run "$REAL"'; GITHUB_TOKEN=tok123; fetch https://api.github.com/x'
check "the release listing sends GITHUB_TOKEN when it is set" \
  file_has "$WORK/curl_args" "Authorization: Bearer tok123"

run "$REAL"'; GITHUB_TOKEN=""; GH_TOKEN=tok456; fetch https://api.github.com/x'
check "the release listing falls back to GH_TOKEN" \
  file_has "$WORK/curl_args" "Authorization: Bearer tok456"

run "$REAL"'; GITHUB_TOKEN=""; GH_TOKEN=""; fetch https://api.github.com/x; grep -c Authorization "$HOME/../curl_args"'
check "the release listing sends no Authorization header without a token" out_is "0"

run "$REAL"'; GITHUB_TOKEN=tok123; download https://github.com/x "$HOME/f"; grep -c tok123 "$HOME/../curl_args"'
check "the token is never sent with a binary download" out_is "0"

run 'FAIL_PAGE=1; do_list'
check "the API failure message mentions GITHUB_TOKEN" err_has "GITHUB_TOKEN"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
