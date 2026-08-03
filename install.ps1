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
  [string] $Prefix,
  [switch] $List,
  [switch] $Help
)

$ErrorActionPreference = "Stop"
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

function Resolve-LatestTag {
  param([string]$name)
  # GitHub returns releases newest-first; the first prefix match is the latest.
  $rels = Invoke-RestMethod -Uri "${Api}?per_page=100" -Headers @{ "User-Agent" = "arpeio-adbc-installer" }
  foreach ($r in $rels) { if ($r.tag_name -like "$name-v*") { return $r.tag_name } }
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

function Show-Usage {
  Write-Info @"
Arpeio ADBC driver installer (Windows)

Usage:
  install.ps1 <driver> [-Version <X.Y.Z|latest>] [-Scope user|system]
              [-License <path>] [-Prefix <dir>]
  install.ps1 -List

Drivers: $($Registry.Keys -join ', ')

The downloaded binary is license-gated: it requires a valid Arpeio licence at
runtime. Re-run with -License <your.lic>, or set ARPEIO_ADBC_LICENCE_FILE, or
place arpeio_adbc.lic next to the installed DLL.
"@
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

  if ($Scope -eq "system") {
    # No auto-searched system directory exists on Windows for .toml manifests
    # (the system mechanism is the registry); install to a stable dir and add it
    # to the machine ADBC_DRIVER_PATH.
    $mandir = Join-Path $env:ProgramData "arpeio-adbc\adbc\drivers"
  } else {
    $mandir = Join-Path $env:LOCALAPPDATA "ADBC\Drivers"
  }

  Write-Info "Installing $name $ver ($manifestKey)"
  Write-Info "  from $url"

  $tmp = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("arpeio-adbc-" + [guid]::NewGuid()))
  try {
    $dest = Join-Path $tmp $asset
    Invoke-WebRequest -Uri $url -OutFile $dest -Headers @{ "User-Agent" = "arpeio-adbc-installer" }

    # Verify checksum against SHA256SUMS if present.
    try {
      $sums = (Invoke-WebRequest -Uri $sumsUrl -Headers @{ "User-Agent" = "arpeio-adbc-installer" }).Content
      $want = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($asset) + '\s*$' } |
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

    if ($License) {
      if (-not (Test-Path $License)) { Fail "licence file not found: $License" }
      Copy-Item -Force $License (Join-Path $libdir "arpeio_adbc.lic")
      Write-Info "  licence installed: $(Join-Path $libdir 'arpeio_adbc.lic')"
    }

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
    if (-not $License -and -not (Test-Path (Join-Path $libdir "arpeio_adbc.lic"))) {
      Write-Info ""
      Write-Info "  ACTION REQUIRED: this driver needs a valid Arpeio licence to load."
      Write-Info "  Re-run with -License <your.lic>, place arpeio_adbc.lic in"
      Write-Info "  $libdir, or set ARPEIO_ADBC_LICENCE_FILE to its path."
    }
    Write-Info ""
    Write-Info "Load it by name, e.g. in Python:"
    Write-Info "  import adbc_driver_manager.dbapi as dbapi"
    Write-Info "  dbapi.connect(driver=`"$name`", db_kwargs={...})"
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

# ---- main --------------------------------------------------------------------
if ($Help) { Show-Usage; return }
if ($List) { Show-List; return }
if (-not $Driver) { Show-List; return }
Install-Driver $Driver
