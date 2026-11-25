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

$Mock = @{ Calls = 0; FailPage = 0; Endless = $false; Download = "fail"; Sums = "ok"; LastAsset = $null
           ApiHeaders = $null; DownloadHeaders = @() }

# Serves the fixture 100 releases per page, honouring `page=N`; counts its calls;
# throws on page $Mock.FailPage; with $Mock.Endless, ignores `page=` altogether.
function Invoke-RestMethod {
  param([string]$Uri, $Headers)
  $Mock.ApiHeaders = $Headers
  $Mock.Calls++
  $page = 1
  if ($Uri -match '[?&]page=(\d+)') { $page = [int]$matches[1] }
  if ($Mock.FailPage -eq $page) { throw "Response status code does not indicate success: 403 (rate limit exceeded)." }
  if ($Mock.Endless) { $page = 1 }
  $slice = @($Fixture | Select-Object -Skip (($page - 1) * 100) -First 100)
  # Like the real cmdlet, hand back the JSON array as a single object.
  return , @($slice | ForEach-Object { [pscustomobject]@{ tag_name = $_ } })
}
# No test may download anything: this fails unless $Mock.Download is "ok". Then it
# writes a fake driver binary, and for SHA256SUMS a matching checksum line - or
# none at all ($Mock.Sums = "missing") or a wrong one ("bad").
function Invoke-WebRequest {
  param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, $Headers)
  $null = $UseBasicParsing
  $Mock.DownloadHeaders += $Headers
  if ($Mock.Download -ne "ok") { throw "download blocked by the test" }
  if ($Uri -like "*/SHA256SUMS") {
    if ($Mock.Sums -eq "missing") { throw "Response status code does not indicate success: 404 (Not Found)." }
    $hash = if ($Mock.Sums -eq "bad") { "0000000000000000" }
            else { (Get-FileHash -Algorithm SHA256 -Path $Mock.LastAsset).Hash.ToLower() }
    Set-Content -Path $OutFile -Value "$hash  $(Split-Path -Leaf $Mock.LastAsset)"
  } else {
    Set-Content -Path $OutFile -Value "driver binary from $Uri"
    $Mock.LastAsset = $OutFile
  }
}

# A -Scope system install must not touch the real machine environment.
function Add-MachineDriverPath { param([string]$mandir) $Mock.MachinePath = $mandir }

$Pass = 0
$Failed = 0
function Reset-State {
  $Mock.Calls = 0; $Mock.FailPage = 0; $Mock.Endless = $false
  $Mock.Download = "fail"; $Mock.Sums = "ok"; $Mock.LastAsset = $null
  $Mock.ApiHeaders = $null; $Mock.DownloadHeaders = @()
  $env:GITHUB_TOKEN = $null; $env:GH_TOKEN = $null
  # A fresh, empty profile for every test.
  $script:TestProfile = Join-Path $Work ([guid]::NewGuid())
  New-Item -ItemType Directory -Path $script:TestProfile | Out-Null
  $env:LOCALAPPDATA = $script:TestProfile
  $env:ProgramFiles = Join-Path $script:TestProfile "ProgramFiles"
  $env:ProgramData = Join-Path $script:TestProfile "ProgramData"
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

# ---- checksum verification ------------------------------------------------------
# Where a default (user-scope) install of arpemssql lands in the scratch profile.
function Get-TestLib { Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA "arpeio-adbc") "arpemssql") "arpemssql_adbc_driver-win-x64.dll" }
function Get-TestManifest { Join-Path (Get-UserManifestDir) "arpemssql.toml" }

Test-Case "an install verifies the download and writes the library and manifest" {
  $Mock.Download = "ok"
  $Version = "0.9.7"
  Install-Driver "arpemssql" *> $null
  (Test-Path (Get-TestLib)) -and ((Read-ManifestVersion (Get-TestManifest)) -eq "0.9.7")
}
Test-Case "a checksum mismatch stops the install and installs nothing" {
  $Mock.Download = "ok"; $Mock.Sums = "bad"
  $Version = "0.9.7"
  $m = Get-Failure { Install-Driver "arpemssql" }
  ($m -match "checksum mismatch") -and -not (Test-Path (Get-TestLib))
}
Test-Case "an install fails when the release SHA256SUMS cannot be downloaded" {
  $Mock.Download = "ok"; $Mock.Sums = "missing"
  $Version = "0.9.7"
  $m = Get-Failure { Install-Driver "arpemssql" }
  ($m -match "SHA256SUMS") -and ($m -match "SkipChecksum")
}
Test-Case "a missing SHA256SUMS installs nothing" {
  $Mock.Download = "ok"; $Mock.Sums = "missing"
  $Version = "0.9.7"
  $null = Get-Failure { Install-Driver "arpemssql" }
  -not (Test-Path (Get-TestLib)) -and -not (Test-Path (Get-TestManifest))
}
Test-Case "-SkipChecksum installs without SHA256SUMS" {
  $Mock.Download = "ok"; $Mock.Sums = "missing"
  $Version = "0.9.7"; $SkipChecksum = $true
  Install-Driver "arpemssql" *> $null
  Test-Path (Get-TestLib)
}
Test-Case "-DownloadOnly fails when the release SHA256SUMS cannot be downloaded" {
  $Mock.Download = "ok"; $Mock.Sums = "missing"
  $Version = "0.9.7"; $Dir = Join-Path $env:LOCALAPPDATA "bundle"
  $m = Get-Failure { Save-Driver "arpemssql" }
  ($m -match "SHA256SUMS") -and -not (Test-Path (Join-Path $Dir "arpemssql_adbc_driver-win-x64.dll"))
}
Test-Case "-DownloadOnly -SkipChecksum downloads without SHA256SUMS" {
  $Mock.Download = "ok"; $Mock.Sums = "missing"
  $Version = "0.9.7"; $SkipChecksum = $true; $Dir = Join-Path $env:LOCALAPPDATA "bundle"
  Save-Driver "arpemssql" *> $null
  Test-Path (Join-Path $Dir "arpemssql_adbc_driver-win-x64.dll")
}

# ---- GitHub token ------------------------------------------------------------------
Test-Case "the release listing sends GITHUB_TOKEN when it is set" {
  $env:GITHUB_TOKEN = "tok123"
  $null = Resolve-LatestTag "arpemssql"
  $Mock.ApiHeaders["Authorization"] -eq "Bearer tok123"
}
Test-Case "the release listing falls back to GH_TOKEN" {
  $env:GH_TOKEN = "tok456"
  $null = Resolve-LatestTag "arpemssql"
  $Mock.ApiHeaders["Authorization"] -eq "Bearer tok456"
}
Test-Case "the release listing sends no Authorization header without a token" {
  $null = Resolve-LatestTag "arpemssql"
  -not $Mock.ApiHeaders.ContainsKey("Authorization")
}
Test-Case "the token is never sent with a binary or SHA256SUMS download" {
  $env:GITHUB_TOKEN = "tok123"
  $Mock.Download = "ok"
  Install-Driver "arpemssql" *> $null
  ($Mock.DownloadHeaders.Count -eq 2) -and
    -not ($Mock.DownloadHeaders | Where-Object { $_.ContainsKey("Authorization") })
}
Test-Case "the API failure message mentions GITHUB_TOKEN" {
  $Mock.FailPage = 1
  (Get-Failure { Show-List }) -match "GITHUB_TOKEN"
}

# ---- -List shows what is installed ----------------------------------------------
# Show-List prints with Write-Host (stream 6); capture it as one string. The
# lines are joined by hand: Out-String would wrap them at the console width
# (80 columns on Windows PowerShell 5.1), cutting a long path in two.
function Get-ListOutput { (Show-List 6>&1 | ForEach-Object { "$_" }) -join "`n" }

Test-Case "-List shows nothing extra for a driver that is not installed" {
  (Get-ListOutput) -notmatch "installed "
}
Test-Case "-List shows an older installed version and flags the update" {
  $Mock.Download = "ok"
  $Version = "0.9.7"; Install-Driver "arpemssql" *> $null
  $Version = "latest"
  (Get-ListOutput) -match "(?m)arpemssql .* 0\.9\.120 .*installed 0\.9\.7, user \(update available\)"
}
Test-Case "-List prints the command that updates an outdated driver" {
  $Mock.Download = "ok"
  $Version = "0.9.7"; Install-Driver "arpemssql" *> $null
  $Version = "latest"
  (Get-ListOutput) -match "(?m)^  install\.ps1 arpemssql\r?$"
}
Test-Case "-List says an installed latest version is up to date, with no update command" {
  $Mock.Download = "ok"
  Install-Driver "arpemssql" *> $null
  $o = Get-ListOutput
  ($o -match "arpemssql .*installed 0\.9\.120, user \(up to date\)") -and ($o -notmatch "Update with")
}
Test-Case "the update command for a -Prefix install repeats the prefix" {
  $Mock.Download = "ok"
  $custom = Join-Path $env:LOCALAPPDATA "custom"
  $Version = "0.9.7"; $Prefix = $custom; Install-Driver "arpemssql" *> $null
  $Version = "latest"; $Prefix = ""
  (Get-ListOutput).Contains("  install.ps1 arpemssql -Prefix $custom")
}
Test-Case "the update command for a system install says -Scope system" {
  $Mock.Download = "ok"
  $Version = "0.9.7"; $Scope = "system"; Install-Driver "arpemssql" *> $null
  $Version = "latest"; $Scope = "user"
  (Get-ListOutput) -match "(?m)^  install\.ps1 arpemssql -Scope system\r?$"
}
# Re-running the install is the update path: it must keep the licence in place.
Test-Case "re-running the install updates the version and keeps the licence" {
  $Mock.Download = "ok"
  $lic = Join-Path $env:LOCALAPPDATA "my.lic"; Set-Content -Path $lic -Value "LIC"
  $Version = "0.9.7"; $License = $lic; Install-Driver "arpemssql" *> $null
  $Version = "latest"; $License = ""; Install-Driver "arpemssql" *> $null
  ((Read-ManifestVersion (Get-TestManifest)) -eq "0.9.120") -and
    (Test-Path (Join-Path (Split-Path -Parent (Get-TestLib)) "arpeio_adbc.lic"))
}

# ---- machine ADBC_DRIVER_PATH (-Scope system) ------------------------------------
Test-Case "the manifest dir becomes the driver path when none is set" {
  (Join-DriverPath "" 'C:\ProgramData\arpeio-adbc\adbc\drivers') -eq 'C:\ProgramData\arpeio-adbc\adbc\drivers'
}
Test-Case "the manifest dir is appended to an existing driver path" {
  (Join-DriverPath 'C:\other\drivers' 'C:\ProgramData\arpeio-adbc\adbc\drivers') -eq
    'C:\other\drivers;C:\ProgramData\arpeio-adbc\adbc\drivers'
}
Test-Case "an existing driver path with several directories is kept whole" {
  (Join-DriverPath 'C:\a;C:\b' 'C:\c') -eq 'C:\a;C:\b;C:\c'
}
Test-Case "a manifest dir already on the driver path is not added twice" {
  (Join-DriverPath 'C:\a;C:\ProgramData\arpeio-adbc\adbc\drivers' 'C:\ProgramData\arpeio-adbc\adbc\drivers') -eq
    'C:\a;C:\ProgramData\arpeio-adbc\adbc\drivers'
}
Test-Case "the driver path comparison ignores case and a trailing backslash" {
  (Join-DriverPath 'c:\programdata\ARPEIO-adbc\adbc\drivers\' 'C:\ProgramData\arpeio-adbc\adbc\drivers') -eq
    'c:\programdata\ARPEIO-adbc\adbc\drivers\'
}
Test-Case "empty entries in the driver path are dropped when appending" {
  (Join-DriverPath 'C:\a;;' 'C:\c') -eq 'C:\a;C:\c'
}

Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "$Pass passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
