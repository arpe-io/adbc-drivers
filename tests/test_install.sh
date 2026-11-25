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
# - download: always fails, so no test ever touches the network or installs.
cat > "$WORK/mocks.sh" <<'EOF'
fetch() {
  printf 'x\n' >> "$CALLS"
  case "$1" in *"&page="*) _pg=${1##*&page=}; _pg=${_pg%%&*} ;; *) _pg=1 ;; esac
  if [ "${FAIL_PAGE:-0}" = "$_pg" ]; then return 22; fi
  awk -v p="$_pg" 'NR > (p - 1) * 100 && NR <= p * 100' "$FIXTURE"
}
download() { return 1; }
EOF

# run <name> <script>: run <script> in a fresh subshell with install.sh and the
# mocks loaded. Leaves stdout in $WORK/out, stderr in $WORK/err, status in $RC.
run() {
  : > "$WORK/calls"
  # The variables below are read by install.sh and the mocks, sourced at run time.
  # shellcheck disable=SC2034
  (
    CALLS="$WORK/calls"; FIXTURE=$FIXTURE
    ARPEIO_ADBC_INSTALL_SOURCE=1
    # shellcheck disable=SC1091
    . "$ROOT/install.sh"
    . "$WORK/mocks.sh"
    VERSION=latest; SCOPE=user; SCOPE_SET=0; PREFIX=""; DIR=""; DRIVER=""
    LICENSE=""; LICENSE_CONTENT=""; SKIP_CHECKSUM=0
    HOME="$WORK/home"
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

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
