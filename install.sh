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

# Verify $tmp/$asset against the release SHA256SUMS (best-effort): a missing
# SHA256SUMS is only a warning, but a checksum mismatch — or a SHA256SUMS with no
# entry for the asset — is fatal.
verify_checksum() { # <sums_url> <asset> <tmp>
  _sums_url=$1; _asset=$2; _tmp=$3
  if download "$_sums_url" "$_tmp/SHA256SUMS" 2>/dev/null; then
    _want=$(grep " $_asset\$" "$_tmp/SHA256SUMS" | awk '{print $1}' | head -n1)
    [ -n "$_want" ] || err "SHA256SUMS has no entry for $_asset"
    _got=$(sha256_of "$_tmp/$_asset")
    [ "$_want" = "$_got" ] || err "checksum mismatch for $_asset (expected $_want, got $_got)"
    info "  checksum OK"
  else
    info "  warning: no SHA256SUMS in the release — skipping checksum verification"
  fi
}

# Detect OS + the two arch spellings we need:
#   ASSET_ARCH  (x64/arm64)   — used in the release asset filename
#   MANIFEST_KEY (linux_amd64…) — the ADBC driver-manager platform tuple
detect_platform() {
  _os=$(uname -s); _machine=$(uname -m)
  case "$_os" in
    Linux)  OS_ASSET=linux; OS_MANIFEST=linux; LIB_PREFIX=lib; LIB_EXT=so ;;
    # macOS is not published yet. The macOS plumbing below (dylib, manifest dirs)
    # is kept intact so this is a one-line re-enable once binaries are ready:
    #   Darwin) OS_ASSET=macos; OS_MANIFEST=macos; LIB_PREFIX=lib; LIB_EXT=dylib ;;
    Darwin) err "macOS is not supported yet (Linux and Windows only for now)" ;;
    *) err "unsupported OS '$_os' (use install.ps1 on Windows)" ;;
  esac
  case "$_machine" in
    x86_64|amd64) ASSET_ARCH=x64;   MANIFEST_ARCH=amd64 ;;
    arm64|aarch64) ASSET_ARCH=arm64; MANIFEST_ARCH=arm64 ;;
    *) err "unsupported architecture '$_machine'" ;;
  esac
  MANIFEST_KEY="${OS_MANIFEST}_${MANIFEST_ARCH}"
}

# All published STABLE versions for a driver, newest-first (empty if none), one
# per line, without the "<name>-v" tag prefix. GitHub returns releases
# newest-first. Prereleases — any version carrying a hyphen, e.g. 0.5.19-rc1 —
# are skipped; install one explicitly with `--version 0.5.19-rc1`.
resolve_versions() {
  fetch "${API}?per_page=100" \
    | grep '"tag_name":' \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' \
    | grep "^$1-v" \
    | while IFS= read -r _t; do
        case "${_t#"$1"-v}" in
          *-*) : ;;                    # prerelease version — skip
          *) printf '%s\n' "${_t#"$1"-v}" ;;
        esac
      done
}

# Latest published STABLE tag for a driver, e.g. "arrowtds-v0.5.19" (empty if
# none) — the newest version from resolve_versions, with the tag prefix restored.
resolve_latest() {
  resolve_versions "$1" | head -n1 | while IFS= read -r _v; do printf '%s\n' "$1-v$_v"; done
}

usage() {
  cat >&2 <<EOF
Arpeio ADBC driver installer

Usage:
  install.sh <driver> [--version <X.Y.Z|latest>] [--user|--system]
             [--license <path> | --license-content <text>] [--prefix <dir>]
  install.sh <driver> --download-only [--version <X.Y.Z|latest>] [--dir <path>]
  install.sh --installed [--user|--system]
  install.sh --uninstall <driver> [--user|--system]
  install.sh --list
  install.sh --versions [<driver>]
  install.sh --help

Drivers: ${ALL_DRIVERS}

Options:
  --version          Driver version to install (default: latest).
  --user             Install for the current user (default): lib under
                     ~/.local/lib/arpeio-adbc, manifest in the user ADBC dir.
  --system           Install system-wide (/opt/arpeio-adbc + system ADBC dir;
                     needs write permission — run with sudo).
  --license          Path to your Arpeio licence (.lic); copied next to the
                     driver as arpeio_adbc.lic.
  --license-content  The licence text itself; written verbatim to arpeio_adbc.lic
                     (handy for CI — note it is visible in the process list).
  --prefix           Override the library install directory.
  --download-only    Just download the driver binary + a ready-to-use manifest into
                     a plain directory (see --dir); no licence is copied, no system
                     dir is touched. Point ADBC_DRIVER_PATH at the dir and supply
                     the licence yourself.
  --dir              Destination directory for --download-only (default: current dir).
  --installed        List the drivers installed on this machine (both scopes by
                     default; narrow with --user/--system).
  --uninstall        Remove a driver: its library, copied licence, and manifest.
                     Acts on the user scope by default; --system for a machine one.
  --list             List the available drivers and their latest published versions.
  --versions         List every published version of each driver (or one driver,
                     if named), newest first.

Licence sources are tried in this order: --license, --license-content,
\$ARPEIO_ADBC_LICENCE_FILE (a path), \$ARPEIO_ADBC_LICENCE (the content). The
downloaded binary is licence-gated: it needs a valid Arpeio licence at runtime.
There is no trial build.
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

# Read fields back out of an installed manifest (source of truth for uninstall).
manifest_version_of() { # <manifest> -> driver version (first `version = ` line)
  grep -E '^version = ' "$1" | sed -E 's/^version = "([^"]+)".*/\1/' | head -n1
}
manifest_libpath_of() { # <manifest> -> the shared library path
  awk -F' = ' '/^\[Driver\.shared\]/{f=1;next} f && / = /{gsub(/"/,"",$2);print $2;exit}' "$1"
}

# Resolve the licence from the first source that is set and write it next to the
# driver as arpeio_adbc.lic. Precedence:
#   --license <file> > --license-content <text> > $ARPEIO_ADBC_LICENCE_FILE
#   (file) > $ARPEIO_ADBC_LICENCE (content). Returns 1 if no source was given.
install_license() { # <libdir>
  _dest="$1/arpeio_adbc.lic"
  if [ -n "${LICENSE:-}" ]; then
    [ -z "${LICENSE_CONTENT:-}" ] || err "pass only one of --license / --license-content"
    [ -f "$LICENSE" ] || err "licence file not found: $LICENSE"
    cp "$LICENSE" "$_dest"; info "  licence installed from --license: $_dest"
  elif [ -n "${LICENSE_CONTENT:-}" ]; then
    printf '%s\n' "$LICENSE_CONTENT" > "$_dest"; info "  licence installed from --license-content: $_dest"
  elif [ -n "${ARPEIO_ADBC_LICENCE_FILE:-}" ]; then
    [ -f "$ARPEIO_ADBC_LICENCE_FILE" ] || err "licence file not found: $ARPEIO_ADBC_LICENCE_FILE"
    cp "$ARPEIO_ADBC_LICENCE_FILE" "$_dest"; info "  licence installed from ARPEIO_ADBC_LICENCE_FILE: $_dest"
  elif [ -n "${ARPEIO_ADBC_LICENCE:-}" ]; then
    printf '%s\n' "$ARPEIO_ADBC_LICENCE" > "$_dest"; info "  licence installed from ARPEIO_ADBC_LICENCE: $_dest"
  else
    return 1
  fi
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

# List every published stable version of each driver (or just one, if a driver
# name is given), newest-first.
do_versions() {
  if [ -n "${DRIVER:-}" ]; then
    driver_field "$DRIVER" lib >/dev/null 2>&1 || err "unknown driver '$DRIVER' (see --list)"
    _drivers=$DRIVER
  else
    _drivers=$ALL_DRIVERS
  fi
  info "Published Arpeio ADBC driver versions (dist: ${DIST_REPO}):"
  info ""
  for d in $_drivers; do
    _joined=""
    for _v in $(resolve_versions "$d"); do _joined="${_joined:+$_joined, }$_v"; done
    [ -n "$_joined" ] || _joined="(not published yet)"
    printf '  %-10s %-22s %s\n' "$d" "$(driver_field "$d" dbms)" "$_joined" >&2
  done
  info ""
  info "Install a specific one:  install.sh <driver> --version <X.Y.Z>"
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
  verify_checksum "$sums_url" "$asset" "$tmp"

  mkdir -p "$libdir" "$mandir" || err "cannot create install dirs (try --user, or sudo for --system)"
  libpath="$libdir/$asset"
  mv "$tmp/$asset" "$libpath"
  chmod 0755 "$libpath"

  # Licence: install it from whichever source was given (see install_license).
  install_license "$libdir" || true

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
  if [ ! -f "$libdir/arpeio_adbc.lic" ]; then
    info ""
    info "  ACTION REQUIRED: this driver needs a valid Arpeio licence to load. Supply"
    info "  it with --license <file> or --license-content <text>, set"
    info "  ARPEIO_ADBC_LICENCE_FILE / ARPEIO_ADBC_LICENCE, or place arpeio_adbc.lic"
    info "  in $libdir."
  fi
  info ""
  info "Load it by name, e.g. in Python:"
  info "  import adbc_driver_manager.dbapi as dbapi"
  info "  dbapi.connect(driver=\"$name\", db_kwargs={...})"
}

# Download the driver binary (and a ready-to-use manifest) into a plain directory,
# without performing a managed install: no licence is copied, no system directory
# is touched, and no env var is set. Destination is --dir (default: current dir).
# The user wires it up themselves (point ADBC_DRIVER_PATH at the dir) and supplies
# the licence on their own.
do_download() {
  name=$1
  driver_field "$name" lib >/dev/null 2>&1 || err "unknown driver '$name' (see --list)"
  detect_platform

  # Resolve version -> tag (same as do_install).
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

  # Destination dir (default: current dir), absolutised so the manifest's library
  # path works regardless of the caller's working directory at load time.
  destdir="${DIR:-.}"
  mkdir -p "$destdir" || err "cannot create directory: $destdir"
  destdir=$(cd "$destdir" && pwd)

  info "Downloading ${name} ${ver} (${MANIFEST_KEY})"
  info "  from ${url}"

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/arpeio-adbc.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT INT TERM
  download "$url" "$tmp/$asset" || err "download failed (is ${name} ${ver} published for ${OS_ASSET}-${ASSET_ARCH}?)"
  verify_checksum "$sums_url" "$asset" "$tmp"

  libpath="$destdir/$asset"
  mv "$tmp/$asset" "$libpath"
  chmod 0755 "$libpath"

  manifest="$destdir/$name.toml"
  write_manifest "$manifest" "$name" "$ver" "$libpath"

  info ""
  info "Downloaded:"
  info "  library:  $libpath"
  info "  manifest: $manifest"
  info ""
  info "To load it by name, point the ADBC driver manager at this directory:"
  info "  export ADBC_DRIVER_PATH=$destdir"
  info ""
  info "  This driver is licence-gated; supply a licence yourself: place your"
  info "  arpeio_adbc.lic next to the library, or set ARPEIO_ADBC_LICENCE_FILE /"
  info "  ARPEIO_ADBC_LICENCE at runtime."
}

# List drivers actually installed on this machine, scanning both the user and
# system locations (or just one if --user/--system was given). The manifest is
# the source of truth; version + library path are read back out of it.
do_installed() {
  detect_platform
  if [ "$SCOPE_SET" = 1 ]; then _scopes=$SCOPE; else _scopes="user system"; fi
  _found=0
  info "Installed Arpeio ADBC drivers:"
  info ""
  for d in $ALL_DRIVERS; do
    for _scope in $_scopes; do
      if [ "$_scope" = user ]; then _mdir=$(user_manifest_dir); else _mdir=$(system_manifest_dir); fi
      _m="$_mdir/$d.toml"
      [ -f "$_m" ] || continue
      _found=1
      _ver=$(manifest_version_of "$_m"); [ -n "$_ver" ] || _ver="?"
      _lp=$(manifest_libpath_of "$_m")
      if [ -n "$_lp" ] && [ -f "$(dirname "$_lp")/arpeio_adbc.lic" ]; then _lic=yes; else _lic=no; fi
      printf '  %-10s %-22s %-9s %-6s licence:%-4s %s\n' \
        "$d" "$(driver_field "$d" dbms)" "$_ver" "$_scope" "$_lic" "$_lp" >&2
    done
  done
  if [ "$_found" = 0 ]; then
    info "  (none installed)"
    info ""
    info "Install one with:  install.sh <driver> --license <your.lic>"
  fi
}

# Remove a driver from a single scope (default user; --system for the machine
# install), matching how install resolves scope. Removes the library, the copied
# licence, the now-empty per-driver dir, and the manifest.
do_uninstall() {
  name=$1
  driver_field "$name" lib >/dev/null 2>&1 || err "unknown driver '$name' (see --list)"
  detect_platform
  if [ "$SCOPE" = system ]; then mandir=$(system_manifest_dir); _other="--user"; else mandir=$(user_manifest_dir); _other="--system"; fi
  manifest="$mandir/$name.toml"
  [ -f "$manifest" ] || err "'$name' is not installed at the $SCOPE level (try $_other?)"

  info "Uninstalling ${name} (${SCOPE})"
  libpath=$(manifest_libpath_of "$manifest")
  if [ -n "$libpath" ] && [ -e "$libpath" ]; then
    libdir=$(dirname "$libpath")
    rm -f "$libpath" || err "cannot remove $libpath (system install? re-run with sudo)"
    info "  removed library:  $libpath"
    if [ -f "$libdir/arpeio_adbc.lic" ]; then
      rm -f "$libdir/arpeio_adbc.lic" && info "  removed licence:  $libdir/arpeio_adbc.lic"
    fi
    if rmdir "$libdir" 2>/dev/null; then info "  removed dir:      $libdir"; fi
  else
    info "  (library from manifest not found on disk; removing manifest only)"
  fi
  rm -f "$manifest" || err "cannot remove $manifest (system install? re-run with sudo)"
  info "  removed manifest: $manifest"
  info ""
  info "Uninstalled ${name}."
}

# Allow `. install.sh` to load the functions without running main (for tests).
if [ "${ARPEIO_ADBC_INSTALL_SOURCE:-}" = 1 ]; then return 0 2>/dev/null || exit 0; fi

# ---- arg parsing -------------------------------------------------------------
DRIVER=""
VERSION="latest"
SCOPE="user"
SCOPE_SET=0
LICENSE=""
LICENSE_CONTENT=""
PREFIX=""
DIR=""
ACTION=install

while [ $# -gt 0 ]; do
  case "$1" in
    --list) ACTION=list ;;
    --versions) ACTION=versions ;;
    --installed) ACTION=installed ;;
    --uninstall) ACTION=uninstall ;;
    --download-only) ACTION=download ;;
    --dir) shift; DIR="${1:?--dir needs a path}" ;;
    --dir=*) DIR="${1#*=}" ;;
    --help|-h) usage; exit 0 ;;
    --version) shift; VERSION="${1:?--version needs a value}" ;;
    --version=*) VERSION="${1#*=}" ;;
    --user) SCOPE="user"; SCOPE_SET=1 ;;
    --system) SCOPE="system"; SCOPE_SET=1 ;;
    --license) shift; LICENSE="${1:?--license needs a path}" ;;
    --license=*) LICENSE="${1#*=}" ;;
    --license-content) shift; LICENSE_CONTENT="${1:?--license-content needs a value}" ;;
    --license-content=*) LICENSE_CONTENT="${1#*=}" ;;
    --prefix) shift; PREFIX="${1:?--prefix needs a dir}" ;;
    --prefix=*) PREFIX="${1#*=}" ;;
    -*) err "unknown option '$1' (see --help)" ;;
    *) [ -z "$DRIVER" ] || err "unexpected argument '$1'"; DRIVER="$1" ;;
  esac
  shift
done

case "$ACTION" in
  list)      have curl || have wget || err "need curl or wget"; do_list ;;
  versions)  have curl || have wget || err "need curl or wget"; do_versions ;;
  installed) do_installed ;;
  uninstall) [ -n "$DRIVER" ] || err "--uninstall needs a driver name (see --installed)"
             do_uninstall "$DRIVER" ;;
  install)   have curl || have wget || err "need curl or wget"
             [ -n "$DRIVER" ] || { usage; exit 2; }
             do_install "$DRIVER" ;;
  download)  have curl || have wget || err "need curl or wget"
             [ -n "$DRIVER" ] || err "--download-only needs a driver name (see --list)"
             do_download "$DRIVER" ;;
esac
