<#
.SYNOPSIS
  Arpeio ADBC driver installer (Windows).

.DESCRIPTION
  Downloads a prebuilt, license-gated Arpeio ADBC driver from the public GitHub
  Releases of arpe-io/adbc-drivers, verifies its checksum, installs the DLL, and
  writes an ADBC driver manifest so the driver can be loaded by name
  (e.g. driver="arrowtds"). The binaries are free to download but require a valid
  Arpeio licence at runtime (no trial build).

.EXAMPLE
  # One-liner (lists drivers when run with no driver):
  irm https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.ps1 | iex

  # With arguments:
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.ps1))) arrowtds -License C:\path\to\your.lic
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string] $Driver,
  [string] $Version = "latest",
  [ValidateSet("user", "system")] [string] $Scope = "user",
  [string] $License,
  [string] $LicenseContent,
  [string] $Prefix,
  [switch] $List,
  [switch] $Versions,
  [switch] $Installed,
  [switch] $Uninstall,
  [switch] $Help
)

$ErrorActionPreference = "Stop"
# Did the caller pass -Scope explicitly? (used to decide whether -Installed scans
# both levels or just one).
$ScopeExplicit = $PSBoundParameters.ContainsKey("Scope")
$DistRepo = "arpe-io/adbc-drivers"
$Api = "https://api.github.com/repos/$DistRepo/releases"
$Dl  = "https://github.com/$DistRepo/releases/download"

$Registry = [ordered]@{
  arrowtds  = @{ display = "ArrowTDS";  dbms = "Microsoft SQL Server"; lib = "arrowtds_adbc_driver"  }
  arrowfebe = @{ display = "ArrowFEBE"; dbms = "PostgreSQL";           lib = "arrowfebe_adbc_driver" }
}

function Write-Info { param([string]$m) Write-Host $m }
function Fail { param([string]$m) Write-Error $m; exit 1 }

function Get-PlatformArch {
  switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { return @{ asset = "x64";   manifest = "amd64" } }
    "ARM64" { return @{ asset = "arm64"; manifest = "arm64" } }
    default { Fail "unsupported architecture '$($env:PROCESSOR_ARCHITECTURE)'" }
  }
}

# The two manifest search dirs. On Windows the system mechanism is really the
# registry; we install/scan a stable ProgramData dir added to ADBC_DRIVER_PATH.
function Get-UserManifestDir   { Join-Path $env:LOCALAPPDATA "ADBC\Drivers" }
function Get-SystemManifestDir { Join-Path $env:ProgramData "arpeio-adbc\adbc\drivers" }

# Read fields back out of an installed manifest (source of truth for uninstall).
function Read-ManifestVersion {
  param([string]$path)
  # First `version = "..."` line is the driver version (the [ADBC] one follows).
  $m = Select-String -Path $path -Pattern '^version = "([^"]+)"' | Select-Object -First 1
  if ($m) { return $m.Matches[0].Groups[1].Value }
  return $null
}
function Read-ManifestLibPath {
  param([string]$path)
  $inShared = $false
  foreach ($line in (Get-Content -Path $path)) {
    if ($line -match '^\[Driver\.shared\]') { $inShared = $true; continue }
    if ($inShared -and $line -match '= "(.+)"\s*$') {
      # Install writes doubled backslashes for valid TOML; unescape them.
      return ($matches[1] -replace '\\\\', '\')
    }
  }
  return $null
}

# All published STABLE versions for a driver, newest-first (empty array if none),
# without the "<name>-v" tag prefix. GitHub returns releases newest-first.
# Prereleases (any version carrying a hyphen, e.g. 0.5.19-rc1) are skipped;
# install one explicitly with -Version 0.5.19-rc1.
function Resolve-Version {
  param([string]$name)
  $rels = Invoke-RestMethod -Uri "${Api}?per_page=100" -Headers @{ "User-Agent" = "arpeio-adbc-installer" }
  $out = @()
  foreach ($r in $rels) {
    if ($r.tag_name -like "$name-v*") {
      $rest = $r.tag_name.Substring("$name-v".Length)
      if ($rest -notmatch '-') { $out += $rest }
    }
  }
  return $out
}

# Latest published STABLE tag for a driver, e.g. "arrowtds-v0.5.19" (null if none)
# - the newest version from Resolve-Version, with the tag prefix restored.
function Resolve-LatestTag {
  param([string]$name)
  $vers = Resolve-Version $name
  if ($vers.Count -gt 0) { return "$name-v$($vers[0])" }
  return $null
}

function Show-List {
  Write-Info "Available Arpeio ADBC drivers (dist: $DistRepo):"
  Write-Info ""
  foreach ($name in $Registry.Keys) {
    $tag = Resolve-LatestTag $name
    $ver = if ($tag) { $tag.Substring("$name-v".Length) } else { "(not published yet)" }
    Write-Info ("  {0,-10} {1,-22} {2}" -f $name, $Registry[$name].dbms, $ver)
  }
  Write-Info ""
  Write-Info "Install:  install.ps1 arrowtds -License C:\path\to\your.lic"
}

# List every published stable version of each driver (or just one, if a driver
# name is given), newest-first.
function Show-Version {
  param([string]$name)
  $drivers = if ($name) {
    if (-not $Registry.Contains($name)) { Fail "unknown driver '$name' (try -List)" }
    @($name)
  } else { @($Registry.Keys) }
  Write-Info "Published Arpeio ADBC driver versions (dist: $DistRepo):"
  Write-Info ""
  foreach ($d in $drivers) {
    $vers = Resolve-Version $d
    $shown = if ($vers.Count -gt 0) { $vers -join ", " } else { "(not published yet)" }
    Write-Info ("  {0,-10} {1,-22} {2}" -f $d, $Registry[$d].dbms, $shown)
  }
  Write-Info ""
  Write-Info "Install a specific one:  install.ps1 <driver> -Version X.Y.Z"
}

function Show-Usage {
  Write-Info @"
Arpeio ADBC driver installer (Windows)

Usage:
  install.ps1 <driver> [-Version <X.Y.Z|latest>] [-Scope user|system]
              [-License <path> | -LicenseContent <text>] [-Prefix <dir>]
  install.ps1 -Installed [-Scope user|system]
  install.ps1 -Uninstall <driver> [-Scope user|system]
  install.ps1 -List
  install.ps1 -Versions [<driver>]

Drivers: $($Registry.Keys -join ', ')

  -License         Path to your Arpeio licence (.lic); copied next to the driver.
  -LicenseContent  The licence text itself; written verbatim to arpeio_adbc.lic.
  -Versions        List every published version of each driver (or one driver,
                   if named), newest first.
  -Installed       List the drivers installed on this machine (both scopes by
                   default; narrow with -Scope).
  -Uninstall <d>   Remove a driver (its library, copied licence, and manifest;
                   -Scope system for a machine install).

Licence sources are tried in order: -License, -LicenseContent,
`$env:ARPEIO_ADBC_LICENCE_FILE (a path), `$env:ARPEIO_ADBC_LICENCE (the content).
The downloaded binary is licence-gated: it needs a valid Arpeio licence at
runtime. There is no trial build.
"@
}

# Resolve the licence from the first source that is set and write it next to the
# driver as arpeio_adbc.lic. Precedence:
#   -License <file> > -LicenseContent <text> > $env:ARPEIO_ADBC_LICENCE_FILE
#   (file) > $env:ARPEIO_ADBC_LICENCE (content). No-op if no source was given.
function Install-License {
  param([string]$libdir)
  $licDest = Join-Path $libdir "arpeio_adbc.lic"
  if ($License) {
    if ($LicenseContent) { Fail "pass only one of -License / -LicenseContent" }
    if (-not (Test-Path $License)) { Fail "licence file not found: $License" }
    Copy-Item -Force $License $licDest
    Write-Info "  licence installed from -License: $licDest"
  } elseif ($LicenseContent) {
    Set-Content -Path $licDest -Value $LicenseContent -Encoding UTF8
    Write-Info "  licence installed from -LicenseContent: $licDest"
  } elseif ($env:ARPEIO_ADBC_LICENCE_FILE) {
    if (-not (Test-Path $env:ARPEIO_ADBC_LICENCE_FILE)) { Fail "licence file not found: $($env:ARPEIO_ADBC_LICENCE_FILE)" }
    Copy-Item -Force $env:ARPEIO_ADBC_LICENCE_FILE $licDest
    Write-Info "  licence installed from ARPEIO_ADBC_LICENCE_FILE: $licDest"
  } elseif ($env:ARPEIO_ADBC_LICENCE) {
    Set-Content -Path $licDest -Value $env:ARPEIO_ADBC_LICENCE -Encoding UTF8
    Write-Info "  licence installed from ARPEIO_ADBC_LICENCE: $licDest"
  }
}

function Install-Driver {
  param([string]$name)
  if (-not $Registry.Contains($name)) { Fail "unknown driver '$name' (try -List)" }
  $arch = Get-PlatformArch
  $lib  = $Registry[$name].lib

  if ($Version -eq "latest") {
    $tag = Resolve-LatestTag $name
    if (-not $tag) { Fail "no published release for '$name' yet" }
  } else {
    $v = $Version -replace '^v', ''
    $tag = "$name-v$v"
  }
  $ver = $tag.Substring("$name-v".Length)

  $asset   = "$lib-win-$($arch.asset).dll"
  $url     = "$Dl/$tag/$asset"
  $sumsUrl = "$Dl/$tag/SHA256SUMS"
  $manifestKey = "windows_$($arch.manifest)"

  if ($Prefix)              { $libdir = Join-Path $Prefix $name }
  elseif ($Scope -eq "system") { $libdir = Join-Path $env:ProgramFiles "arpeio-adbc\$name" }
  else                      { $libdir = Join-Path $env:LOCALAPPDATA "arpeio-adbc\$name" }

  # No auto-searched system directory exists on Windows for .toml manifests (the
  # system mechanism is the registry); -Scope system installs to a stable
  # ProgramData dir added to the machine ADBC_DRIVER_PATH.
  if ($Scope -eq "system") { $mandir = Get-SystemManifestDir } else { $mandir = Get-UserManifestDir }

  Write-Info "Installing $name $ver ($manifestKey)"
  Write-Info "  from $url"

  $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("arpeio-adbc-" + [guid]::NewGuid()))
  try {
    $dest = Join-Path $tmp $asset
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -Headers @{ "User-Agent" = "arpeio-adbc-installer" }

    # Verify checksum against SHA256SUMS if present.
    try {
      # Download to a file and read it back as text. On Windows PowerShell 5.1,
      # Invoke-WebRequest returns .Content as a byte[] (not a string) for
      # application/octet-stream responses like SHA256SUMS, so an in-memory
      # `.Content -split` splits each byte individually and never matches.
      # -OutFile + Get-Content -Raw always yields text; -UseBasicParsing also
      # avoids the IE DOM parser (the "risque d'execution de script" prompt) on 5.1.
      $sumsFile = Join-Path $tmp "SHA256SUMS"
      Invoke-WebRequest -Uri $sumsUrl -OutFile $sumsFile -UseBasicParsing -Headers @{ "User-Agent" = "arpeio-adbc-installer" }
      $sums = Get-Content -Raw -Path $sumsFile
      # Match on the exact filename field (last whitespace-delimited token) so the
      # parse is immune to CRLF vs LF and trailing whitespace.
      $want = ($sums -split "`r?`n" |
               ForEach-Object { $_.Trim() } |
               Where-Object { ($_ -split '\s+')[-1] -eq $asset } |
               ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1)
      if (-not $want) { Fail "SHA256SUMS has no entry for $asset" }
      $got = (Get-FileHash -Algorithm SHA256 -Path $dest).Hash.ToLower()
      if ($want.ToLower() -ne $got) { Fail "checksum mismatch for $asset" }
      Write-Info "  checksum OK"
    } catch [System.Net.WebException] {
      Write-Info "  warning: no SHA256SUMS in the release - skipping checksum verification"
    }

    New-Item -ItemType Directory -Force -Path $libdir, $mandir | Out-Null
    $libpath = Join-Path $libdir $asset
    Move-Item -Force $dest $libpath

    # Licence: install it from whichever source was given (see Install-License).
    Install-License $libdir
    $licDest = Join-Path $libdir "arpeio_adbc.lic"

    # The manifest path must use doubled backslashes to be a valid TOML string.
    $tomlPath = $libpath -replace '\\', '\\'
    $manifest = @"
# Generated by the Arpeio ADBC installer - do not edit by hand.
manifest_version = 1
name = "$($Registry[$name].display) ADBC Driver"
version = "$ver"
publisher = "Arpeio"

[ADBC]
version = "1.1.0"

[Driver]
entrypoint = "AdbcDriverInit"

[Driver.shared]
$manifestKey = "$tomlPath"
"@
    $manifestFile = Join-Path $mandir "$name.toml"
    Set-Content -Path $manifestFile -Value $manifest -Encoding UTF8

    Write-Info ""
    Write-Info "Installed:"
    Write-Info "  library:  $libpath"
    Write-Info "  manifest: $manifestFile"
    if ($Scope -eq "system") {
      [Environment]::SetEnvironmentVariable("ADBC_DRIVER_PATH", $mandir, "Machine")
      Write-Info "  (added $mandir to the machine ADBC_DRIVER_PATH; open a new shell)"
    }
    if (-not (Test-Path $licDest)) {
      Write-Info ""
      Write-Info "  ACTION REQUIRED: this driver needs a valid Arpeio licence to load."
      Write-Info "  Supply it with -License <file> or -LicenseContent <text>, set"
      Write-Info "  ARPEIO_ADBC_LICENCE_FILE / ARPEIO_ADBC_LICENCE, or place"
      Write-Info "  arpeio_adbc.lic in $libdir."
    }
    Write-Info ""
    Write-Info "Load it by name, e.g. in Python:"
    Write-Info "  import adbc_driver_manager.dbapi as dbapi"
    Write-Info "  dbapi.connect(driver=`"$name`", db_kwargs={...})"
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

# List drivers actually installed on this machine, scanning both the user and
# system locations (or just one if -Scope was given). The manifest is the source
# of truth; version + library path are read back out of it.
function Show-Installed {
  $scopes = if ($ScopeExplicit) { @($Scope) } else { @("user", "system") }
  $found = $false
  Write-Info "Installed Arpeio ADBC drivers:"
  Write-Info ""
  foreach ($name in $Registry.Keys) {
    foreach ($scope in $scopes) {
      $mdir = if ($scope -eq "system") { Get-SystemManifestDir } else { Get-UserManifestDir }
      $manifest = Join-Path $mdir "$name.toml"
      if (-not (Test-Path $manifest)) { continue }
      $found = $true
      $ver = Read-ManifestVersion $manifest; if (-not $ver) { $ver = "?" }
      $lp  = Read-ManifestLibPath $manifest
      $lic = if ($lp -and (Test-Path (Join-Path (Split-Path $lp -Parent) "arpeio_adbc.lic"))) { "yes" } else { "no" }
      Write-Info ("  {0,-10} {1,-22} {2,-9} {3,-6} licence:{4,-4} {5}" -f `
        $name, $Registry[$name].dbms, $ver, $scope, $lic, $lp)
    }
  }
  if (-not $found) {
    Write-Info "  (none installed)"
    Write-Info ""
    Write-Info "Install one with:  install.ps1 <driver> -License C:\path\to\your.lic"
  }
}

# Remove a driver from a single scope (default user; -Scope system for the
# machine install), matching how install resolves scope. Removes the library,
# the copied licence, the now-empty per-driver dir, and the manifest.
function Uninstall-Driver {
  param([string]$name)
  if (-not $Registry.Contains($name)) { Fail "unknown driver '$name' (try -List)" }
  if ($Scope -eq "system") { $mdir = Get-SystemManifestDir; $other = "-Scope user" }
  else                     { $mdir = Get-UserManifestDir;   $other = "-Scope system" }
  $manifest = Join-Path $mdir "$name.toml"
  if (-not (Test-Path $manifest)) { Fail "'$name' is not installed at the $Scope level (try ${other}?)" }

  Write-Info "Uninstalling $name ($Scope)"
  try {
    $libpath = Read-ManifestLibPath $manifest
    if ($libpath -and (Test-Path $libpath)) {
      $libdir = Split-Path $libpath -Parent
      Remove-Item -Force $libpath
      Write-Info "  removed library:  $libpath"
      $lic = Join-Path $libdir "arpeio_adbc.lic"
      if (Test-Path $lic) { Remove-Item -Force $lic; Write-Info "  removed licence:  $lic" }
      if ((Get-ChildItem -Force $libdir -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Remove-Item -Force $libdir; Write-Info "  removed dir:      $libdir"
      }
    } else {
      Write-Info "  (library from manifest not found on disk; removing manifest only)"
    }
    Remove-Item -Force $manifest
    Write-Info "  removed manifest: $manifest"
  } catch {
    Fail "could not remove $name (system install? re-run in an elevated shell): $_"
  }
  # We intentionally leave the machine ADBC_DRIVER_PATH env var (set by a -Scope
  # system install) in place; it is harmless if the dir is empty.
  Write-Info ""
  Write-Info "Uninstalled $name."
}

# Allow dot-sourcing to load the functions without running main (for tests).
if ($env:ARPEIO_ADBC_INSTALL_SOURCE -eq "1") { return }

# ---- main --------------------------------------------------------------------
if ($Help) { Show-Usage; return }
if ($Installed) { Show-Installed; return }
if ($Uninstall) {
  if (-not $Driver) { Fail "-Uninstall needs a driver name (see -Installed)" }
  Uninstall-Driver $Driver; return
}
if ($List) { Show-List; return }
if ($Versions) { Show-Version $Driver; return }
if (-not $Driver) { Show-List; return }
Install-Driver $Driver
