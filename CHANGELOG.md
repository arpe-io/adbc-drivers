# Changelog

Changes to the Arpeio ADBC **installers** (`install.sh`, `install.ps1`) and the
driver registry. The drivers themselves are versioned and released separately,
under `<driver>-v<version>` tags; their release notes are on the
[documentation site](https://adbc-drivers-docs.arpe.io/).

The install one-liners run the installer from the `main` branch, so a change
reaches users when it is merged there, whether or not a version has been tagged.

## Unreleased

Everything since v0.2.2. Not tagged yet.

### Breaking

- **The driver load names changed** with the commercial rebrand: `arrowtds` is now
  `arpemssql`, `arrowfebe` is `arpepgsql`, `arrowttc` is `arpeoracle`. The old
  names no longer resolve. Release tags, binaries and manifests follow the new
  names.
- **An install stops when the release `SHA256SUMS` cannot be downloaded.** It used
  to print a warning and install the unverified binary. `--skip-checksum` /
  `-SkipChecksum`, previously offline-only, continues without verification in
  every mode.
- **arm64 machines are rejected** with `arm64 is not supported yet`: only x64
  binaries are published. The install used to fail later, on a missing download.

### Added

- **Offline / air-gapped install.** `--download-only` now also saves the release
  `SHA256SUMS`, and `--offline` / `-Offline` performs a managed install from that
  bundle with no network access. A bundle without `SHA256SUMS` is refused.
- **Three more drivers**: ArpeNetezza (`arpenz`), ArpeTeradata (`arpeteradata`)
  and ArpeDb2 (`arpedb2`).
- **`--list` / `-List` shows what is installed**: the installed version next to
  the latest one, whether it is up to date, and the command that updates it.
  `--installed` is unchanged and still works without network access.
- **Optional GitHub token.** If `GITHUB_TOKEN` or `GH_TOKEN` is set, it is sent
  with the API call that lists the releases (and only that call), which lifts
  GitHub's limit of 60 unauthenticated requests per hour per IP address.
- **Tests** for both installers (`tests/`), run in CI on Linux and Windows,
  including Windows PowerShell 5.1, and a scheduled smoke test against the real
  releases.

### Fixed

- **`latest` is the highest version.** The installers took the first release
  GitHub lists, which is not in version order: 0.4.9 could be installed while
  0.4.10 existed.
- **Every page of the release listing is read.** Only the first 100 releases were,
  and all the drivers share one listing: past 100 releases a driver could have
  been reported as not published.
- **A failed GitHub API call is reported as such**, instead of "no published
  release".
- **`install.ps1 -Scope system` no longer replaces the machine `ADBC_DRIVER_PATH`.**
  It appends its directory and keeps the ones already there.
- **`install.ps1` resolves `latest` when a driver has a single published version**;
  it used to build a wrong tag and fail the download.

### Docs

- The README links to the documentation site at its current address, and to the
  ArpeDb2 page.

## v0.2.2 — 2026-08-08

### Added

- ArrowTTC (Oracle) is installable by name.
- `--download-only` / `-DownloadOnly`: download and checksum-verify a driver
  binary and write a ready-to-use manifest next to it, into a directory of your
  choice (`--dir` / `-Dir`), with no managed install.

### Fixed

- Checksum verification on Windows PowerShell 5.1: `SHA256SUMS` is read from a
  downloaded file, and `-UseBasicParsing` is used.

### Docs

- A driver-selection table and a troubleshooting section in the README.

## v0.2.1 — 2026-08-04

### Added

- `--versions [driver]` / `-Versions [driver]`: list every published stable
  version of each driver, newest first.

### Changed

- macOS is explicitly rejected as not yet supported, instead of attempting an
  install that cannot succeed.

## v0.2.0 — 2026-08-04

### Added

- More ways to supply the licence at install time: `--license-content` /
  `-LicenseContent`, and the `ARPEIO_ADBC_LICENCE_FILE` and `ARPEIO_ADBC_LICENCE`
  environment variables.
- MIT licence for the installers, registry and docs.
- CI linting (`shellcheck`, `PSScriptAnalyzer`), `CONTRIBUTING.md`, pull request
  and issue templates.

## v0.1.0 — 2026-08-04

First tagged release of the installers.

### Added

- `--installed` / `-Installed`: list the drivers installed on this machine.
- `--uninstall <driver>` / `-Uninstall <driver>`: remove a driver's library, its
  copied licence and its manifest.
