# Arpeio ADBC drivers

[![CI](https://github.com/arpe-io/adbc-drivers/actions/workflows/lint.yml/badge.svg)](https://github.com/arpe-io/adbc-drivers/actions/workflows/lint.yml)
[![installer](https://img.shields.io/badge/installer-v0.2.1-2b8a3e)](https://github.com/arpe-io/adbc-drivers/releases)
[![License: MIT](https://img.shields.io/github/license/arpe-io/adbc-drivers)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-Linux%20%7C%20Windows-informational)

One-line installers for the Arpeio family of [ADBC](https://arrow.apache.org/adbc/)
drivers. Each driver is a pure-native, high-performance ADBC driver that returns
Apache Arrow directly — install it with a single command, then load it by name
from any ADBC client.

### Which driver do I need?

| Your database | Driver | Load name | Status |
|---|---|---|---|
| Microsoft SQL Server (incl. Azure SQL, Fabric) | [ArrowTDS](https://github.com/aetperf/ArrowTDS) | `arrowtds` | ✅ Published |
| PostgreSQL | [ArrowFEBE](https://github.com/aetperf/ArrowFEBE) | `arrowfebe` | ✅ Published |
| Oracle | [ArrowTTC](https://github.com/aetperf/ArrowTTC) | `arrowttc` | 🚧 Coming soon |
| IBM Db2 | [ArrowDRDA](https://github.com/aetperf/ArrowDRDA) | `arrowdrda` | 🚧 Coming soon |

Only the drivers marked **Published** are downloadable today; run
`… install.sh --list` for the authoritative, always-current list. Each driver's
own repository (linked above) has its connection guide, data-type mapping, and
compatibility matrix.

The driver *binaries* are published here as public GitHub Releases and are free
to download. They are **licence-gated**: a driver requires a valid Arpeio licence
at runtime — there is no trial build. Contact <sales@arpe.io> for a licence.

## Install

**Linux / macOS:**

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh \
  | sh -s -- arrowtds --license /path/to/your.lic
```

**Windows (PowerShell):**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.ps1))) `
  arrowtds -License C:\path\to\your.lic
```

List what's available and the latest published version of each:

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh | sh -s -- --list
```

List **every** published version (all drivers, or a single one), newest first:

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh | sh -s -- --versions arrowtds
```

## What the installer does

1. Downloads the driver's shared library for your OS/arch from this repo's
   Releases (tag `<driver>-v<version>`, e.g. `arrowtds-v0.5.19`) and verifies it
   against the release `SHA256SUMS`.
2. Installs the library (default: per-user, under `~/.local/lib/arpeio-adbc/`
   on Unix / `%LOCALAPPDATA%\arpeio-adbc\` on Windows; `--system` / `-Scope
   system` for a machine-wide install).
3. Writes an **ADBC driver manifest** (`<driver>.toml`) into the ADBC driver
   manager's search path, so the driver loads by name:

   ```python
   import adbc_driver_manager.dbapi as dbapi
   with dbapi.connect(driver="arrowtds",
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

**Linux / macOS:**

```sh
curl -fsSL https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.sh \
  | sh -s -- arrowtds --download-only --dir ./drivers
```

**Windows (PowerShell):**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/arpe-io/adbc-drivers/main/install.ps1))) `
  arrowtds -DownloadOnly -Dir .\drivers
```

To load the driver by name afterwards, point the ADBC driver manager at that
directory (`export ADBC_DRIVER_PATH=./drivers`, or `setx ADBC_DRIVER_PATH` on
Windows), and supply a licence yourself — place your `arpeio_adbc.lic` next to the
library, or set `ARPEIO_ADBC_LICENCE_FILE` / `ARPEIO_ADBC_LICENCE` at runtime (see
[Supplying the licence](#supplying-the-licence)).

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
  | sh -s -- --uninstall arrowtds
```

Uninstall acts on your per-user install by default; add `--system` (with `sudo`)
to remove a machine-wide one. On Windows, use `-Installed` and
`-Uninstall arrowtds` (an elevated shell for `-Scope system`).

## Options

| `install.sh` | `install.ps1` | Meaning |
|---|---|---|
| `--version X.Y.Z` | `-Version X.Y.Z` | Install a specific version (default: `latest`). |
| `--user` (default) | `-Scope user` | Per-user install (no admin). |
| `--system` | `-Scope system` | Machine-wide install (needs sudo/admin). |
| `--license <path>` | `-License <path>` | Install your `.lic` file next to the driver. |
| `--license-content <text>` | `-LicenseContent <text>` | Install the licence from inline text. |
| `--prefix <dir>` | `-Prefix <dir>` | Override the library install directory. |
| `--download-only` | `-DownloadOnly` | Just download the binary + manifest into a dir (see [Download only](#download-only)); no managed install. |
| `--dir <dir>` | `-Dir <dir>` | Destination directory for `--download-only` (default: current dir). |
| `--list` | `-List` | List *available* drivers + latest published versions. |
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
... install.sh arrowtds --license /path/to/your.lic
# from a secret in CI (bash)
ARPEIO_ADBC_LICENCE="$MY_LICENCE_SECRET" ... install.sh arrowtds
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
`~/.config/adbc/drivers` (Linux) · `~/Library/Application Support/ADBC/Drivers`
(macOS) · `%LOCALAPPDATA%\ADBC\Drivers` (Windows), or the system equivalents with
`--system`. If your client can't find it, point `ADBC_DRIVER_PATH` at the
directory the installer reports.

## Troubleshooting

**Checksum verification failed.** The download did not match the release
`SHA256SUMS` — usually a truncated download or a proxy rewriting the response.
Re-run the installer; if it persists, download the release asset manually from the
[Releases](https://github.com/arpe-io/adbc-drivers/releases) page and compare with
`sha256sum`.

**Client can't find the driver / "driver not found".** The ADBC driver manager did
not see the manifest. Confirm the install with `… install.sh --installed`, then
point `ADBC_DRIVER_PATH` at the directory the installer reports (see
[Manifest search paths](#manifest-search-paths-advanced)). Make sure the client
loads by the exact **load name** (`arrowtds`, `arrowfebe`, …).

**Connection fails with an `ARROW_LIC_*` error.** The driver loaded but found no
valid licence at runtime. Install one next to the driver (`--license`), or set
`ARPEIO_ADBC_LICENCE_FILE` / `ARPEIO_ADBC_LICENCE` — see
[Supplying the licence](#supplying-the-licence). Each driver repo's `LICENSING.md`
has the full resolution order.

**Permission denied during `--system` install.** System-wide installs write to
`/opt/arpeio-adbc` and the system ADBC directory — run with `sudo` (Unix) or an
elevated shell (`-Scope system` on Windows). Or drop `--system` for a per-user
install that needs no admin.

**`macOS is not supported yet`.** macOS binaries are staged but not yet published;
use Linux or Windows for now.

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
