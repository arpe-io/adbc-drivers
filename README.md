# Arpeio ADBC drivers

[![CI](https://github.com/arpe-io/adbc-drivers/actions/workflows/lint.yml/badge.svg)](https://github.com/arpe-io/adbc-drivers/actions/workflows/lint.yml)
[![installer](https://img.shields.io/badge/installer-v0.2.3-2b8a3e)](https://github.com/arpe-io/adbc-drivers/releases)
[![License: MIT](https://img.shields.io/github/license/arpe-io/adbc-drivers)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Linux%20x64%20%7C%20Windows%20x64-informational)
[![Docs](https://img.shields.io/badge/docs-adbc--drivers--docs.arpe.io-1f6feb)](https://adbc-drivers-docs.arpe.io/)

One-line installers for the Arpeio family of [ADBC](https://arrow.apache.org/adbc/)
drivers. Each driver is a pure-native, high-performance ADBC driver that returns
Apache Arrow directly — install it with a single command, then load it by name
from any ADBC client.

📖 **Documentation:** <https://adbc-drivers-docs.arpe.io/> —
installation, per-driver connection guides, authentication, data-type mappings,
compatibility, and troubleshooting.

### Which driver do I need?

| Your database | Driver | Load name | Status |
|---|---|---|---|
| Microsoft SQL Server (incl. Azure SQL, Fabric) | ArpeMSSQL | `arpemssql` | ✅ Published |
| PostgreSQL | ArpePGSQL | `arpepgsql` | ✅ Published |
| Oracle | ArpeOracle | `arpeoracle` | ✅ Published |
| IBM Netezza | ArpeNetezza | `arpenz` | ✅ Published |
| Teradata | ArpeTeradata | `arpeteradata` | ✅ Published |
| IBM Db2 | ArpeDb2 | `arpedb2` | ✅ Published |

All six drivers are published for Linux x64 and Windows x64; run
`… install.sh --list` for the latest version of each. Each driver's connection
guide, data-type mapping, and compatibility matrix live on the
[documentation site](https://adbc-drivers-docs.arpe.io/) —
[ArpeMSSQL](https://adbc-drivers-docs.arpe.io/drivers/arpemssql),
[ArpePGSQL](https://adbc-drivers-docs.arpe.io/drivers/arpepgsql),
[ArpeOracle](https://adbc-drivers-docs.arpe.io/drivers/arpeoracle),
[ArpeNetezza](https://adbc-drivers-docs.arpe.io/drivers/arpenetezza),
[ArpeTeradata](https://adbc-drivers-docs.arpe.io/drivers/arpeteradata),
[ArpeDb2](https://adbc-drivers-docs.arpe.io/drivers/arpedb2).

The driver *binaries* are published here as public GitHub Releases and are free
to download. They are **licence-gated**: a driver requires a valid Arpeio licence
at runtime — there is no trial build. Contact <sales@arpe.io> for a licence.

## Install

**Linux:**

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh \
  | sh -s -- arpemssql --license /path/to/your.lic
```

**Windows (PowerShell):**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.ps1))) `
  arpemssql -License C:\path\to\your.lic
```

List what's available and the latest published version of each:

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh | sh -s -- --list
```

For a driver that is already installed, the same list shows the installed version
next to the latest one, and prints the command that updates it:

```text
  arpemssql    Microsoft SQL Server   0.8.4      installed 0.8.3, user (update available)
  ...
Update with (your licence file stays in place):
  install.sh arpemssql
```

Updating is simply installing again: the new library replaces the old one in the
same directory, and the licence file next to it is left alone.

List **every** published version (all drivers, or a single one), newest first:

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh | sh -s -- --versions arpemssql
```

## What the installer does

1. Downloads the driver's shared library for your OS/arch from this repo's
   Releases (tag `<driver>-v<version>`, e.g. `arpemssql-v0.8.4`) and verifies it
   against the release `SHA256SUMS`. Nothing is installed if the checksum does
   not match or the `SHA256SUMS` cannot be downloaded.
2. Installs the library (default: per-user, under `~/.local/lib/arpeio-adbc/`
   on Unix / `%LOCALAPPDATA%\arpeio-adbc\` on Windows; `--system` / `-Scope
   system` for a machine-wide install).
3. Writes an **ADBC driver manifest** (`<driver>.toml`) into the ADBC driver
   manager's search path, so the driver loads by name:

   ```python
   import adbc_driver_manager.dbapi as dbapi
   with dbapi.connect(driver="arpemssql",
                      db_kwargs={"uri": "sqlserver://sa:<pw>@host:1433/?database=db&encrypt=true"}) as conn:
       ...
   ```
4. If you pass `--license <path>`, copies it next to the library as
   `arpeio_adbc.lic` (where the driver looks for it by default).

## Download only

If you'd rather manage the deployment yourself — a custom path, a container image,
an air-gapped copy, your own licence handling — use `--download-only` /
`-DownloadOnly`. It downloads and checksum-verifies the driver binary and writes a
ready-to-use `<driver>.toml` manifest **next to it**, into the directory you choose
with `--dir` / `-Dir` (default: the current directory). Nothing else is touched: no
system directory, no licence file, no environment variable.

**Linux:**

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh \
  | sh -s -- arpemssql --download-only --dir ./drivers
```

**Windows (PowerShell):**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.ps1))) `
  arpemssql -DownloadOnly -Dir .\drivers
```

To load the driver by name afterwards, point the ADBC driver manager at that
directory (`export ADBC_DRIVER_PATH=./drivers`, or `setx ADBC_DRIVER_PATH` on
Windows), and supply a licence yourself — place your `arpeio_adbc.lic` next to the
library, or set `ARPEIO_ADBC_LICENCE_FILE` / `ARPEIO_ADBC_LICENCE` at runtime (see
[Supplying the licence](#supplying-the-licence)).

If instead you want a normal **managed** install on a machine with no internet, keep
this bundle and finish with `--offline` on the target — see below.

## Offline / air-gapped install

For a machine with no internet, install in two phases across two machines. The
target gets a normal **managed** install — standard install location, an ADBC
manifest in the driver-manager directory, and your licence — with **no network
access at install time**.

> **Both machines must share the same OS and CPU architecture** (the driver binary
> is platform-specific), and you obtain your `.lic` separately from Arpeio
> (`sales@arpe.io`) and carry it across yourself.

**Phase 1 — on an online machine** (same OS/arch as the target): save the installer,
then download the driver bundle. `--download-only` writes the driver binary, a
`<driver>.toml` manifest, and the release `SHA256SUMS` into the bundle directory.

Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh -o install.sh
sh install.sh arpemssql --download-only --dir ./arpemssql-bundle
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.ps1 -OutFile install.ps1
.\install.ps1 arpemssql -DownloadOnly -Dir .\arpemssql-bundle
```

Copy `install.sh` (or `install.ps1`), the `arpemssql-bundle` directory, and your
`your.lic` to the offline machine (USB stick, internal transfer, etc.).

**Phase 2 — on the offline machine**: run the installer in offline mode against the
bundle. It re-verifies the binary against the bundled `SHA256SUMS`, installs into the
standard location, writes the ADBC manifest, and copies your licence — all with no
network calls.

Linux:

```sh
sh install.sh arpemssql --offline --dir ./arpemssql-bundle --license ./your.lic
```

Windows (PowerShell):

```powershell
.\install.ps1 arpemssql -Offline -Dir .\arpemssql-bundle -License .\your.lic
```

The version is read from the bundled manifest automatically; pass `--version` /
`-Version` to override it. `--user` / `--system` / `--prefix` work exactly as in a
normal install, and the bundle directory is left intact so you can reuse it (for
another user scope, or another machine of the same platform).

The bundle must contain the `SHA256SUMS` that `--download-only` saved; a missing one
is treated as an incomplete transfer and the install fails. If you deliberately
prepared a bundle without it, pass `--skip-checksum` / `-SkipChecksum` to install
without verification.

## Listing and removing

See what's installed on this machine (scans both the user and system locations,
showing each driver's version, scope, library path, and whether a licence is in
place):

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh \
  | sh -s -- --installed
```

Remove a driver — its library, the copied licence, and its manifest:

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh \
  | sh -s -- --uninstall arpemssql
```

Uninstall acts on your per-user install by default; add `--system` (with `sudo`)
to remove a machine-wide one. On Windows, use `-Installed` and
`-Uninstall arpemssql` (an elevated shell for `-Scope system`).

## Options

| `install.sh` | `install.ps1` | Meaning |
|---|---|---|
| `--version X.Y.Z` | `-Version X.Y.Z` | Install a specific version (default: `latest`). |
| `--user` (default) | `-Scope user` | Per-user install (no admin). |
| `--system` | `-Scope system` | Machine-wide install (needs sudo/admin). |
| `--license <path>` | `-License <path>` | Install your `.lic` file next to the driver. |
| `--license-content <text>` | `-LicenseContent <text>` | Install the licence from inline text. |
| `--prefix <dir>` | `-Prefix <dir>` | Override the library install directory. |
| `--download-only` | `-DownloadOnly` | Just download the binary + manifest + `SHA256SUMS` into a dir (see [Download only](#download-only)); no managed install. |
| `--offline` | `-Offline` | Managed install from a pre-downloaded bundle with no network (see [Offline / air-gapped install](#offline--air-gapped-install)). |
| `--dir <dir>` | `-Dir <dir>` | Bundle directory: destination for `--download-only`, source for `--offline` (default: current dir). |
| `--skip-checksum` | `-SkipChecksum` | Continue without checksum verification. By default a `SHA256SUMS` that is missing or cannot be downloaded stops the command. |
| `--list` | `-List` | List *available* drivers + latest published versions, with the installed version of each and how to update it. |
| `--versions [<driver>]` | `-Versions [<driver>]` | List *every* published version (all drivers, or one). |
| `--installed` | `-Installed` | List the drivers *installed* on this machine. |
| `--uninstall <driver>` | `-Uninstall <driver>` | Remove an installed driver. |

## Supplying the licence

The installer does not bundle a licence — you provide your own. It writes it next
to the driver as `arpeio_adbc.lic`.

### At install time

Give the installer the licence in any of these ways; it uses the **first** one it
finds, in this order:

| Order | `install.sh` | `install.ps1` | Source |
|---|---|---|---|
| 1 | `--license <path>` | `-License <path>` | Copy an existing `.lic` **file**. |
| 2 | `--license-content <text>` | `-LicenseContent <text>` | The licence **text** itself, written verbatim. |
| 3 | `ARPEIO_ADBC_LICENCE_FILE` | `ARPEIO_ADBC_LICENCE_FILE` | Env var holding a **path** to a `.lic` file. |
| 4 | `ARPEIO_ADBC_LICENCE` | `ARPEIO_ADBC_LICENCE` | Env var holding the licence **content**. |

Passing both `--license` and `--license-content` is an error. The env-var forms are
the safest for CI/secrets; a licence passed inline on the command line is visible
in the shell history and process list.

```sh
# from a file
... install.sh arpemssql --license /path/to/your.lic
# from a secret in CI (bash)
ARPEIO_ADBC_LICENCE="$MY_LICENCE_SECRET" ... install.sh arpemssql
```

### At runtime

Alternatively, don't install a licence file and let the **driver** find one at
connect time. It checks, in order:

1. the `arpeio.adbc.license` / `arpeio.adbc.license_file` ADBC database option;
2. the `ARPEIO_ADBC_LICENCE` / `ARPEIO_ADBC_LICENCE_FILE` environment variable;
3. a file named `arpeio_adbc.lic` next to the installed driver library
   (what the install-time options above set up for you).

## Manifest search paths (advanced)

The installer writes `<driver>.toml` where the ADBC driver manager searches:
`~/.config/adbc/drivers` (Linux) · `%LOCALAPPDATA%\ADBC\Drivers` (Windows), or
the system equivalents with `--system`. If your client can't find it, point `ADBC_DRIVER_PATH` at the
directory the installer reports.

## Troubleshooting

**Checksum verification failed.** The download did not match the release
`SHA256SUMS` — usually a truncated download or a proxy rewriting the response.
Re-run the installer; if it persists, download the release asset manually from the
[Releases](https://github.com/arpe-io/adbc-drivers/releases) page and compare with
`sha256sum`.

**`could not download the release SHA256SUMS`.** The installer refuses to install a
binary it cannot verify. This is usually a network hiccup: re-run the command.
`--skip-checksum` / `-SkipChecksum` continues without verification, at your own
risk.

**Client can't find the driver / "driver not found".** The ADBC driver manager did
not see the manifest. Confirm the install with `… install.sh --installed`, then
point `ADBC_DRIVER_PATH` at the directory the installer reports (see
[Manifest search paths](#manifest-search-paths-advanced)). Make sure the client
loads by the exact **load name** (`arpemssql`, `arpepgsql`, …).

**Connection fails with an `ARROW_LIC_*` error.** The driver loaded but found no
valid licence at runtime. Install one next to the driver (`--license`), or set
`ARPEIO_ADBC_LICENCE_FILE` / `ARPEIO_ADBC_LICENCE` — see
[Supplying the licence](#supplying-the-licence). Each driver's Licensing page on
the documentation site has the full resolution order — see for example
[ArpeMSSQL → Licensing](https://adbc-drivers-docs.arpe.io/drivers/arpemssql/licensing).

**Permission denied during `--system` install.** System-wide installs write to
`/opt/arpeio-adbc` and the system ADBC directory — run with `sudo` (Unix) or an
elevated shell (`-Scope system` on Windows). Or drop `--system` for a per-user
install that needs no admin.

**`macOS is not supported yet`.** Only Linux x64 and Windows x64 binaries are
published; use one of those for now.

**`arm64 is not supported yet`.** Only x64 binaries are published for now, on both
Linux and Windows; use an x64 machine.

**`could not list the releases … from the GitHub API`.** Finding the latest version
reads the public GitHub API, which allows 60 unauthenticated requests per hour per
IP address — a limit a shared CI runner or office network can reach. Retry later,
or name the version: `--version X.Y.Z` (`-Version X.Y.Z` on Windows) installs
without calling the API. In CI, set `GITHUB_TOKEN` (or `GH_TOKEN`) to a GitHub
token: the installer sends it with that API call only, which lifts the limit.

## Building from source

The driver sources are proprietary and live in private repositories. This repo
hosts only the installers, the driver registry (`registry.json`), and the
published binaries.

## Contributing

Contributions to the installers, registry, and docs are welcome. Please read
[CONTRIBUTING.md](CONTRIBUTING.md) — in short: fork, branch off `develop`, run the
linters (`shellcheck` / `PSScriptAnalyzer`), and open a PR into `develop`.

## Licence

The contents of this repository (installers, registry, docs) are released under
the [MIT License](LICENSE). The driver **binaries** downloaded by the installer
are a separate, proprietary product and remain licence-gated at runtime — contact
<sales@arpe.io> for a licence.
