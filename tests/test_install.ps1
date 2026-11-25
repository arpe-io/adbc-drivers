# Tests for install.ps1 - no network: Invoke-RestMethod (the GitHub API) and
# Invoke-WebRequest (the binary download) are replaced by functions.
#
#   pwsh -NoProfile -File tests/test_install.ps1
#
# install.ps1 is dot-sourced through its ARPEIO_ADBC_INSTALL_SOURCE hook, which
# loads the functions without running main. Written for PowerShell 7 (any OS)
# and Windows PowerShell 5.1; so far only run on PowerShell 7.
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path ([IO.Path]::GetTempPath()) ("arpeio-adbc-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Work | Out-Null

# The install locations are built from these; point them at the scratch dir so the
# tests behave the same on Windows and elsewhere, and never touch a real profile.
$env:LOCALAPPDATA = $Work
$env:TEMP = $Work
$env:PROCESSOR_ARCHITECTURE = "AMD64"

$env:ARPEIO_ADBC_INSTALL_SOURCE = "1"
. (Join-Path $Root "install.ps1")

# A release listing in the order the GitHub API returns it: 120 arpemssql
# releases first, then the only two arpeteradata ones - which therefore sit
# beyond the first page of 100.
$Fixture = @()
foreach ($i in 120..1) { $Fixture += "arpemssql-v0.9.$i" }
$Fixture += "arpeteradata-v0.3.8", "arpeteradata-v0.3.6"

$Mock = @{ Calls = 0; FailPage = 0; Endless = $false }

# Serves the fixture 100 releases per page, honouring `page=N`; counts its calls;
# throws on page $Mock.FailPage; with $Mock.Endless, ignores `page=` altogether.
function Invoke-RestMethod {
  param([string]$Uri, $Headers)
  $null = $Headers
  $Mock.Calls++
  $page = 1
  if ($Uri -match '[?&]page=(\d+)') { $page = [int]$matches[1] }
  if ($Mock.FailPage -eq $page) { throw "Response status code does not indicate success: 403 (rate limit exceeded)." }
  if ($Mock.Endless) { $page = 1 }
  $slice = @($Fixture | Select-Object -Skip (($page - 1) * 100) -First 100)
  # Like the real cmdlet, hand back the JSON array as a single object.
  return , @($slice | ForEach-Object { [pscustomobject]@{ tag_name = $_ } })
}
# No test may download anything.
function Invoke-WebRequest { throw "download blocked by the test" }

$Pass = 0
$Failed = 0
function Reset-State {
  $Mock.Calls = 0; $Mock.FailPage = 0; $Mock.Endless = $false
  if ($null -ne $ReleaseCache) { $ReleaseCache.Tags = $null }
  $env:PROCESSOR_ARCHITECTURE = "AMD64"
}
# Run $Body from a clean state; the test passes when it returns $true.
function Test-Case {
  param([string]$Name, [scriptblock]$Body)
  Reset-State
  $detail = ""
  $ok = $false
  try { $ok = [bool](& $Body) } catch { $detail = "threw: $_" }
  if ($ok) { $script:Pass++; Write-Host "ok   - $Name" }
  else { $script:Failed++; Write-Host "FAIL - $Name"; if ($detail) { Write-Host "       $detail" } }
}
# Run $Body and return the message of the error it raises ("" if it raises none).
function Get-Failure {
  param([scriptblock]$Body)
  try { & $Body *> $null } catch { return "$_" }
  return ""
}

# ---- pagination ----------------------------------------------------------------
Test-Case "latest is found for a driver whose releases are all past the first 100" {
  (Resolve-LatestTag "arpeteradata") -eq "arpeteradata-v0.3.8"
}
Test-Case "every version is listed when a driver's releases span two pages" {
  @(Resolve-Version "arpemssql").Count -eq 120
}
Test-Case "latest is the highest version across pages" {
  (Resolve-LatestTag "arpemssql") -eq "arpemssql-v0.9.120"
}
Test-Case "-List reads the release listing once (2 pages), not once per driver" {
  Show-List *> $null
  $Mock.Calls -eq 2
}

# ---- API failure ---------------------------------------------------------------
Test-Case "-List reports a page that cannot be fetched as an API failure" {
  $Mock.FailPage = 2
  (Get-Failure { Show-List }) -match "GitHub API"
}
Test-Case "installing latest reports an API failure, not 'no published release'" {
  $Mock.FailPage = 1
  $Version = "latest"
  $m = Get-Failure { Install-Driver "arpemssql" }
  ($m -match "GitHub API") -and ($m -notmatch "no published release")
}
Test-Case "-DownloadOnly of latest reports the API failure" {
  $Mock.FailPage = 1
  $Version = "latest"
  (Get-Failure { Save-Driver "arpemssql" }) -match "GitHub API"
}
Test-Case "an endless listing stops with an error" {
  $Mock.Endless = $true
  (Get-Failure { Show-List }) -match "GitHub API"
}

# ---- pinned version ------------------------------------------------------------
Test-Case "installing a pinned version makes no API call" {
  $Version = "0.9.7"
  $m = Get-Failure { Install-Driver "arpemssql" }
  ($Mock.Calls -eq 0) -and ($m -match "download blocked")
}

# ---- architecture --------------------------------------------------------------
Test-Case "arm64 is rejected with a clear message" {
  $env:PROCESSOR_ARCHITECTURE = "ARM64"
  (Get-Failure { Get-PlatformArch }) -match "arm64 is not supported yet"
}
Test-Case "arm64 is rejected before any download is attempted" {
  $env:PROCESSOR_ARCHITECTURE = "ARM64"
  $Version = "0.9.7"
  $m = Get-Failure { Install-Driver "arpemssql" }
  ($m -match "arm64 is not supported yet") -and ($m -notmatch "download blocked")
}
Test-Case "x64 is still accepted" {
  (Get-PlatformArch).manifest -eq "amd64"
}

Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "$Pass passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
