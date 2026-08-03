#!/bin/sh
# Arpeio ADBC driver installer (Linux / macOS).
#
#   curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh | sh -s -- <driver> [options]
#   curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh | sh -s -- --list
#
# Downloads a prebuilt, license-gated Arpeio ADBC driver from the public
# GitHub Releases of arpe-io/adbc-drivers, verifies its checksum, installs the
# shared library, and writes an ADBC driver manifest so the driver can be loaded
# by name (e.g. driver="arrowtds"). The binaries are free to download but require
# a valid Arpeio licence at runtime — see --license below.
#
# Dependencies: sh, curl (or wget), and sha256sum (Linux) or shasum (macOS).
set -eu

DIST_REPO="arpe-io/adbc-drivers"
API="https://api.github.com/repos/${DIST_REPO}/releases"
DL="https://github.com/${DIST_REPO}/releases/download"

# ---- registry (mirror of registry.json; kept small + dependency-free) --------
# driver_field <name> <field>  where field ∈ lib|display|dbms
driver_field() {
  case "$1" in
    arrowtds)  _lib=arrowtds_adbc_driver;  _display=ArrowTDS;  _dbms="Microsoft SQL Server" ;;
    arrowfebe) _lib=arrowfebe_adbc_driver; _display=ArrowFEBE; _dbms="PostgreSQL" ;;
    *) return 1 ;;
  esac
  case "$2" in
    lib) printf '%s\n' "$_lib" ;;
    display) printf '%s\n' "$_display" ;;
    dbms) printf '%s\n' "$_dbms" ;;
  esac
}
ALL_DRIVERS="arrowtds arrowfebe"

# ---- helpers -----------------------------------------------------------------
info() { printf '%s\n' "$*" >&2; }
err()  { printf 'error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

fetch() { # url -> stdout
  if have curl; then curl -fsSL "$1"; else wget -qO- "$1"; fi
}
download() { # url dest
  if have curl; then curl -fSL --retry 3 -o "$2" "$1"; else wget -q -O "$2" "$1"; fi
}
sha256_of() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}';
  elif have shasum; then shasum -a 256 "$1" | awk '{print $1}';
  else err "need sha256sum or shasum to verify the download"; fi
}

# Detect OS + the two arch spellings we need:
#   ASSET_ARCH  (x64/arm64)   — used in the release asset filename
#   MANIFEST_KEY (linux_amd64…) — the ADBC driver-manager platform tuple
detect_platform() {
  _os=$(uname -s); _machine=$(uname -m)
  case "$_os" in
    Linux)  OS_ASSET=linux; OS_MANIFEST=linux; LIB_PREFIX=lib; LIB_EXT=so ;;
    Darwin) OS_ASSET=macos; OS_MANIFEST=macos; LIB_PREFIX=lib; LIB_EXT=dylib ;;
    *) err "unsupported OS '$_os' (use install.ps1 on Windows)" ;;
  esac
  case "$_machine" in
    x86_64|amd64) ASSET_ARCH=x64;   MANIFEST_ARCH=amd64 ;;
    arm64|aarch64) ASSET_ARCH=arm64; MANIFEST_ARCH=arm64 ;;
    *) err "unsupported architecture '$_machine'" ;;
  esac
  MANIFEST_KEY="${OS_MANIFEST}_${MANIFEST_ARCH}"
}

# Latest published STABLE tag for a driver, e.g. "arrowtds-v0.5.19" (empty if
# none). GitHub returns releases newest-first, so the first match is the latest.
# Prereleases are skipped: any version carrying a hyphen (e.g.
# arrowtds-v0.5.19-rc1) is treated as a prerelease and ignored by `latest`.
# Install one explicitly with `--version 0.5.19-rc1`.
resolve_latest() {
  fetch "${API}?per_page=100" \
    | grep '"tag_name":' \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' \
    | grep "^$1-v" \
    | while IFS= read -r _t; do
        case "${_t#"$1"-v}" in
          *-*) : ;;                    # prerelease version — skip
          *) printf '%s\n' "$_t" ;;
        esac
      done \
    | head -n1
}

usage() {
  cat >&2 <<EOF
Arpeio ADBC driver installer

Usage:
  install.sh <driver> [--version <X.Y.Z|latest>] [--user|--system]
             [--license <path>] [--prefix <dir>]
  install.sh --list
  install.sh --help

Drivers: ${ALL_DRIVERS}

Options:
  --version   Driver version to install (default: latest).
  --user      Install for the current user (default): lib under
              ~/.local/lib/arpeio-adbc, manifest in the user ADBC dir.
  --system    Install system-wide (/opt/arpeio-adbc + system ADBC dir; needs
              write permission — run with sudo).
  --license   Path to your Arpeio licence (.lic); copied next to the driver as
              arpeio_adbc.lic. Without it, set ARPEIO_ADBC_LICENCE_FILE or place
              arpeio_adbc.lic next to the library yourself before use.
  --prefix    Override the library install directory.
  --list      List the available drivers and their latest published versions.

The downloaded binary is license-gated: it requires a valid Arpeio licence at
runtime. There is no trial build.
EOF
}

# ---- manifest + install locations --------------------------------------------
user_manifest_dir() {
  if [ "$OS_MANIFEST" = macos ]; then
    printf '%s\n' "$HOME/Library/Application Support/ADBC/Drivers"
  else
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/adbc/drivers"
  fi
}
system_manifest_dir() {
  if [ "$OS_MANIFEST" = macos ]; then
    printf '%s\n' "/Library/Application Support/ADBC/Drivers"
  else
    printf '%s\n' "/etc/adbc/drivers"
  fi
}

write_manifest() { # <path> <name> <version> <libpath>
  _mpath=$1; _name=$2; _ver=$3; _libpath=$4
  cat > "$_mpath" <<EOF
# Generated by the Arpeio ADBC installer — do not edit by hand.
manifest_version = 1
name = "$(driver_field "$_name" display) ADBC Driver"
version = "${_ver}"
publisher = "Arpeio"

[ADBC]
version = "1.1.0"

[Driver]
entrypoint = "AdbcDriverInit"

[Driver.shared]
${MANIFEST_KEY} = "${_libpath}"
EOF
}

# ---- commands ----------------------------------------------------------------
do_list() {
  detect_platform
  info "Available Arpeio ADBC drivers (dist: ${DIST_REPO}):"
  info ""
  for d in $ALL_DRIVERS; do
    _tag=$(resolve_latest "$d" || true)
    if [ -n "${_tag:-}" ]; then _ver="${_tag#"$d"-v}"; else _ver="(not published yet)"; fi
    printf '  %-10s %-22s %s\n' "$d" "$(driver_field "$d" dbms)" "$_ver" >&2
  done
  info ""
  info "Install:  install.sh <driver> --license <your.lic>"
}

do_install() {
  name=$1
  driver_field "$name" lib >/dev/null 2>&1 || err "unknown driver '$name' (see --list)"
  detect_platform

  # Resolve version -> tag.
  if [ "$VERSION" = latest ]; then
    tag=$(resolve_latest "$name" || true)
    [ -n "${tag:-}" ] || err "no published release for '$name' yet"
  else
    tag="${name}-v${VERSION#v}"
  fi
  ver="${tag#"$name"-v}"

  lib=$(driver_field "$name" lib)
  asset="${LIB_PREFIX}${lib}-${OS_ASSET}-${ASSET_ARCH}.${LIB_EXT}"
  url="${DL}/${tag}/${asset}"
  sums_url="${DL}/${tag}/SHA256SUMS"

  # Install locations.
  if [ -n "${PREFIX:-}" ]; then libdir="$PREFIX/$name"
  elif [ "$SCOPE" = system ]; then libdir="/opt/arpeio-adbc/$name"
  else libdir="$HOME/.local/lib/arpeio-adbc/$name"; fi
  if [ "$SCOPE" = system ]; then mandir=$(system_manifest_dir); else mandir=$(user_manifest_dir); fi

  info "Installing ${name} ${ver} (${MANIFEST_KEY})"
  info "  from ${url}"

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/arpeio-adbc.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT INT TERM
  download "$url" "$tmp/$asset" || err "download failed (is ${name} ${ver} published for ${OS_ASSET}-${ASSET_ARCH}?)"

  # Verify checksum against the release SHA256SUMS.
  if download "$sums_url" "$tmp/SHA256SUMS" 2>/dev/null; then
    want=$(grep " $asset\$" "$tmp/SHA256SUMS" | awk '{print $1}' | head -n1)
    [ -n "$want" ] || err "SHA256SUMS has no entry for $asset"
    got=$(sha256_of "$tmp/$asset")
    [ "$want" = "$got" ] || err "checksum mismatch for $asset (expected $want, got $got)"
    info "  checksum OK"
  else
    info "  warning: no SHA256SUMS in the release — skipping checksum verification"
  fi

  mkdir -p "$libdir" "$mandir" || err "cannot create install dirs (try --user, or sudo for --system)"
  libpath="$libdir/$asset"
  mv "$tmp/$asset" "$libpath"
  chmod 0755 "$libpath"

  # Licence: copy next to the lib, or explain how to supply it.
  if [ -n "${LICENSE:-}" ]; then
    [ -f "$LICENSE" ] || err "licence file not found: $LICENSE"
    cp "$LICENSE" "$libdir/arpeio_adbc.lic"
    info "  licence installed: $libdir/arpeio_adbc.lic"
  fi

  manifest="$mandir/$name.toml"
  write_manifest "$manifest" "$name" "$ver" "$libpath"

  info ""
  info "Installed:"
  info "  library:  $libpath"
  info "  manifest: $manifest"
  if [ "$SCOPE" != system ] && [ "$OS_MANIFEST" != macos ]; then
    info "  (user manifest dir; if your ADBC client doesn't find it, set"
    info "   ADBC_DRIVER_PATH=$mandir)"
  fi
  if [ -z "${LICENSE:-}" ] && [ ! -f "$libdir/arpeio_adbc.lic" ]; then
    info ""
    info "  ACTION REQUIRED: this driver needs a valid Arpeio licence to load."
    info "  Either re-run with --license <your.lic>, place arpeio_adbc.lic in"
    info "  $libdir, or set ARPEIO_ADBC_LICENCE_FILE to its path."
  fi
  info ""
  info "Load it by name, e.g. in Python:"
  info "  import adbc_driver_manager.dbapi as dbapi"
  info "  dbapi.connect(driver=\"$name\", db_kwargs={...})"
}

# Allow `. install.sh` to load the functions without running main (for tests).
if [ "${ARPEIO_ADBC_INSTALL_SOURCE:-}" = 1 ]; then return 0 2>/dev/null || exit 0; fi

# ---- arg parsing -------------------------------------------------------------
DRIVER=""
VERSION="latest"
SCOPE="user"
LICENSE=""
PREFIX=""
LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST=1 ;;
    --help|-h) usage; exit 0 ;;
    --version) shift; VERSION="${1:?--version needs a value}" ;;
    --version=*) VERSION="${1#*=}" ;;
    --user) SCOPE="user" ;;
    --system) SCOPE="system" ;;
    --license) shift; LICENSE="${1:?--license needs a path}" ;;
    --license=*) LICENSE="${1#*=}" ;;
    --prefix) shift; PREFIX="${1:?--prefix needs a dir}" ;;
    --prefix=*) PREFIX="${1#*=}" ;;
    -*) err "unknown option '$1' (see --help)" ;;
    *) [ -z "$DRIVER" ] || err "unexpected argument '$1'"; DRIVER="$1" ;;
  esac
  shift
done

have curl || have wget || err "need curl or wget"

if [ "$LIST" = 1 ]; then do_list; exit 0; fi
[ -n "$DRIVER" ] || { usage; exit 2; }
do_install "$DRIVER"
