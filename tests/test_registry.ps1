# Checks that the driver list is the same in its four copies: registry.json,
# install.sh, install.ps1 and the README table. Nothing reads registry.json at
# install time (the installers carry their own copy so they stay a single
# dependency-free file), so only this test keeps the copies from drifting.
#
#   pwsh -NoProfile -File tests/test_registry.ps1
#
# Needs `sh` on the PATH (it asks install.sh for its copy).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

# registry.json is the reference: "name|display|dbms|lib", in file order.
$json = Get-Content -Raw -Path (Join-Path $Root "registry.json") | ConvertFrom-Json
$expected = @($json.drivers.PSObject.Properties | ForEach-Object {
    "{0}|{1}|{2}|{3}" -f $_.Name, $_.Value.display, $_.Value.dbms, $_.Value.lib })

# install.ps1: its $Registry table.
$env:ARPEIO_ADBC_INSTALL_SOURCE = "1"
. (Join-Path $Root "install.ps1")
$fromPs1 = @($Registry.Keys | ForEach-Object {
    "{0}|{1}|{2}|{3}" -f $_, $Registry[$_].display, $Registry[$_].dbms, $Registry[$_].lib })

# install.sh: ALL_DRIVERS and driver_field.
$probe = '. "$1"; for d in $ALL_DRIVERS; do printf "%s|%s|%s|%s\n" "$d" "$(driver_field "$d" display)" "$(driver_field "$d" dbms)" "$(driver_field "$d" lib)"; done'
$fromSh = @(& sh -c $probe _ (Join-Path $Root "install.sh"))

# README: the "Which driver do I need?" table - | database | Display | `name` | status |
$fromReadme = @(Get-Content -Path (Join-Path $Root "README.md") | ForEach-Object {
    if ($_ -match '^\|[^|]+\|\s*(\w+)\s*\|\s*`(\w+)`\s*\|') { "{0}|{1}" -f $matches[2], $matches[1] } })
$expectedReadme = @($expected | ForEach-Object { ($_ -split '\|')[0..1] -join '|' })

$Failed = 0
function Compare-List {
  param([string]$what, [string[]]$want, [string[]]$got)
  if (($want -join "`n") -ceq ($got -join "`n")) { Write-Host "ok   - $what matches registry.json"; return }
  $script:Failed++
  Write-Host "FAIL - $what differs from registry.json"
  Write-Host "       registry.json: $($want -join '  ')"
  Write-Host "       ${what}: $($got -join '  ')"
}
Compare-List "install.sh" $expected $fromSh
Compare-List "install.ps1" $expected $fromPs1
Compare-List "README.md driver table" $expectedReadme $fromReadme

# The entrypoint is written into every manifest by both installers.
$entry = @($json.drivers.PSObject.Properties | ForEach-Object { $_.Value.entrypoint } | Sort-Object -Unique)
if (($entry.Count -eq 1) -and ($entry[0] -ceq "AdbcDriverInit")) { Write-Host "ok   - every driver uses the AdbcDriverInit entrypoint the installers write" }
else { $Failed++; Write-Host "FAIL - registry.json entrypoints are not all AdbcDriverInit: $($entry -join ', ')" }

Write-Host ""
if ($Failed -gt 0) { Write-Host "$Failed check(s) failed"; exit 1 }
Write-Host "driver list is in sync"
