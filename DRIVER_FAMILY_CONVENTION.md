# Arpeio ADBC driver-family convention

The single source of truth for the conventions shared by every Arpeio ADBC
driver. The drivers live in separate (private) repositories and speak different
wire protocols, but they present **one consistent surface** to an ADBC client:
the same load-by-name mechanism, the same environment variables, the same
licence gate, the same option namespace shape, and connection URIs that each
follow their own database's ecosystem.

This document is normative for maintainers. When a new driver joins the family,
or an existing one grows a feature, it should match what is written here — and if
a deliberate divergence is needed, this file is where it gets recorded.

The family today:

| Driver | Database | Load name | Wire protocol | Source repo | Default branch |
|---|---|---|---|---|---|
| **ArrowTDS** | Microsoft SQL Server (incl. Azure SQL, Fabric) | `arrowtds` | MS-TDS | `aetperf/ArrowTDS` | `develop` → `main` |
| **ArrowFEBE** | PostgreSQL | `arrowfebe` | FEBE v3 | `aetperf/ArrowFEBE` | `develop` → `main` |
| **ArrowTTC** | Oracle | `arrowttc` | TNS + TTC | `aetperf/ArrowTTC` | `develop` → `main` |
| **ArrowDRDA** | IBM Db2 | `arrowdrda` | DRDA | `aetperf/ArrowDRDA` | `main` (no CI yet) |

`<code>` below is the lowercase driver code — `tds`, `febe`, `ttc`, `drda` — and
`<Code>` its capitalised form (`TDS`, `FEBE`, `TTC`, `DRDA`).

---

## 1. Naming

| Thing | Convention | Examples |
|---|---|---|
| Load name / manifest name | branded `arrow<code>` | `arrowtds`, `arrowfebe`, `arrowttc`, `arrowdrda` |
| Shared library | `arrow<code>_adbc_driver` | `libarrowtds_adbc_driver.so`, `arrowfebe_adbc_driver.dll` |
| Primary entrypoint | `AdbcDriverInit` | (identical across the family) |
| Named entrypoint | `AdbcDriverArrow<Code>Init` | `AdbcDriverArrowTDSInit`, `AdbcDriverArrowDRDAInit` |
| Option namespace | `adbc.arrow<code>.*` | `adbc.arrowtds.database`, `adbc.arrowttc.service_name` |
| Version macro | `ARROW<CODE>_DRIVER_VERSION` | in `adbc_driver_arrow<code>.h`, the single source of truth |

The **branded** load name is deliberate: it never collides on the driver
manager's name table, so an Arpeio driver coexists with any other driver for the
same database (e.g. `arrowtds` alongside a third-party `mssql`).

---

## 2. Driver manifest (load-by-name)

Each driver's CMake `install` generates and installs an ADBC **driver manifest**
`arrow<code>.toml` into `<prefix>/etc/adbc/drivers/`, so a client loads it by
name rather than by absolute library path:

```python
import adbc_driver_manager.dbapi as dbapi
with dbapi.connect(driver="arrowtds", db_kwargs={"uri": "..."}) as conn:
    ...
```

Manifest invariants:

- `manifest_version = 1`; `[ADBC] version = "1.1.0"`.
- `[Driver] entrypoint = "AdbcDriverInit"`.
- `[Driver.shared]` keyed by the ADBC platform tuple (`linux_amd64`,
  `windows_amd64`, `macos_arm64`, …) → the installed library path.
- `version` is parsed from the `ARROW<CODE>_DRIVER_VERSION` macro at configure
  time, so it can never drift from what the driver reports via `GetInfo`.
- The install **prefix is baked at configure time** — pass
  `-DCMAKE_INSTALL_PREFIX=...` when configuring, not `--install --prefix`.

The public installer in this repo writes its **own** manifest (it knows the real
install path at install time); the CMake-generated one is for source/`cmake
--install` users.

---

## 3. Symbol visibility

The shared library exports **only the two ADBC entrypoints**
(`AdbcDriverInit`, `AdbcDriverArrow<Code>Init`) — nothing else. This shrinks the
ABI surface and stops another library in the same process interposing an internal
helper.

- **ELF (Linux):** a linker version script `core/arrow<code>_exports.map`
  (`global:` the two entrypoints, `local: *`). The `local: *` also localises
  statically linked archive symbols.
- **Windows:** a module-definition file `core/arrow<code>_exports.def`, with
  `WINDOWS_EXPORT_ALL_SYMBOLS` **off**.
- **macOS:** `-exported_symbols_list` (added with the macOS build).

Verify with `nm -D` (ELF) / `dumpbin /exports` (Windows): the dynamic export
table should contain exactly the two names.

---

## 4. Environment variables

**Two namespaces, each variable in exactly one — no aliases, no shims.**

- **Generic, family-wide** diagnostic/behaviour knobs use the shared
  **`ARPEIO_ADBC_*`** prefix, so one variable configures every driver and traces
  from different drivers compare directly.
- **Driver- or protocol-specific** knobs keep the **`ARROW<CODE>_*`** prefix.

| Variable | Namespace | Meaning | Drivers |
|---|---|---|---|
| `ARPEIO_ADBC_READ_TIMING` | shared | per-batch read profiling | TDS, FEBE, TTC |
| `ARPEIO_ADBC_WRITE_TIMING` | shared | per-batch ingest profiling | FEBE |
| `ARPEIO_ADBC_ALLOCATOR` | shared | `system` vs mimalloc A/B | TDS, FEBE, TTC |
| `ARPEIO_ADBC_QUIET` | shared | silence non-error diagnostics | TDS |
| `ARROWTDS_TDS_READ_DEBUG`, `ARROWTDS_USE_TDS_RPC` | TDS-specific | TDS wire debugging / RPC path | TDS |
| `ARROWTTC_NO_LOB_PREFETCH` | TTC-specific | Oracle LOB prefetch escape hatch | TTC |

The rule, not the table, is normative: a knob that would mean the same thing for
every driver belongs in `ARPEIO_ADBC_*`; one with no analogue elsewhere stays
`ARROW<CODE>_*`. When a driver adds a generic knob, use the shared prefix from
day one. See each repo's `docs/ENV_VARS.md` for its full list.

---

## 5. Licence

Every driver embeds the same Arpeio ARROW LICENCE validator and resolves a
licence from, in order:

1. the `arpeio.adbc.license` (inline token) / `arpeio.adbc.license_file` (path)
   ADBC database option;
2. the **`ARPEIO_ADBC_LICENCE`** / **`ARPEIO_ADBC_LICENCE_FILE`** environment
   variable (British spelling — shared across the family);
3. a file named **`arpeio_adbc.lic`** next to the driver library.

The read-only `arpeio.adbc.license.status` database option reports
`<state>;code=<ARROW_LIC_*>;tier=<tier>;expires=<epoch>`. Builds are **dev-mode**
(validate and report, never block) unless compiled with
`-DARROW<CODE>_LICENSE_ENFORCE=ON`. There is no trial build; the runtime gate —
not repo access — protects the product.

---

## 6. Connection interface

Three ways to point a driver at a server, all landing in the same internal
fields via a shared field-mask merge:

### 6a. Discrete options — `adbc.arrow<code>.*`

Structured options in the driver's namespace (`adbc.arrowtds.server`,
`adbc.arrowttc.service_name`, …), plus the ADBC-standard `username` / `password`
/ `adbc.connection.catalog` / `adbc.connection.db_schema` where they apply.

### 6b. `connection_string` — ADO.NET `key=value;` form

`adbc.arrow<code>.connection_string` accepts the ADO.NET-style
`Server=...;Database=...;User ID=...;Password=...;` grammar (case-insensitive
keywords, quoted values, doubled-quote escapes). The tokenizer is shared; each
driver adds its own keyword table.

### 6c. `uri` — one branded/standard URL front door **per database ecosystem**

The standard ADBC `uri` option takes a `<scheme>://...` URL. **Each driver's URI
grammar follows its own database's ecosystem** rather than one shared grammar —
so a Postgres user writes a libpq URL, an Oracle user writes an Oracle URL, and
each reads exactly as that community expects:

| Driver | Schemes | Path segment | Notable query params |
|---|---|---|---|
| **ArrowTDS** | `sqlserver` · `mssql` · `arrowtds` | **instance** name (db via `?database=`) | `encrypt`, `trustServerCertificate`, `connection timeout`, `packet size`, `app name` |
| **ArrowFEBE** | `postgresql` · `postgres` · `arrowfebe` | **database** name (libpq) | `sslmode`, `channel_binding`, `sslrootcert`, `gssencmode`, `connect_timeout`, `application_name` |
| **ArrowTTC** | `oracle` · `arrowttc` | **service name** (`?sid=` for the SID form) | `ssl_mode`, `wallet_location`, `wallet_password`, `encryption`, `data_integrity`, `proxy_user`, `number_mapping` |
| **ArrowDRDA** | `db2` · `arrowdrda` | **database** name | `user`, `password`, `database`/`dbname` |

Shared URI behaviour across all four:

- Grammar shape `<scheme>://[user[:password]@]host[:port][/<path>][?k=v&…]`;
  scheme case-insensitive; a `uri` with no `<scheme>://` is rejected with a
  message pointing at `connection_string`.
- userinfo, host, and query values are **percent-decoded**; `+` in a query value
  decodes to a space; bracketed IPv6 hosts (`[::1]:1433`) are supported.
- An unknown query parameter, or one that repeats a value already given in the
  URI, is rejected.
- The **branded `arrow<code>` scheme** always works and never collides — useful
  when more than one driver for the same database is installed.

### Precedence (all three forms)

Discrete `adbc.arrow<code>.*` options **always win** over a value from
`connection_string` or `uri`, regardless of the order they are set. This is
enforced by a per-field bitmask (`ARROW<CODE>_FIELD_*`) shared between the parsed
result and the database handle — the merge applies a parsed field only if no
discrete option already claimed it. Secrets held transiently on the stack during
parsing are scrubbed (`OPENSSL_cleanse`) on every return path.

---

## 7. ADBC surface

Every driver targets **ADBC 1.1.0** and implements the full vtable: query,
prepared statements + bind, bulk ingest, `GetObjects` / `GetTableSchema` /
`GetTableTypes` / `GetStatistics` / `GetInfo`, commit/rollback, typed options,
`ExecuteSchema`, structured error details, and `AdbcDriverInit`. `GetInfo`
answers all seven standard codes (vendor/driver name+version, driver ADBC and
Arrow versions).

---

## 8. Versioning & release

- `ARROW<CODE>_DRIVER_VERSION` in `adbc_driver_arrow<code>.h` is the **single
  source of truth**; the manifest, `GetInfo`, and release tags all derive from
  it.
- A driver repo tags `v<X.Y.Z>`; its CI builds every platform, auto-creates the
  private release (source/NuGet for the .NET consumer), and **cross-publishes**
  the licence-gated binaries + `SHA256SUMS` to this public repo under a
  `arrow<code>-v<X.Y.Z>` release (guarded on the `ARPEIO_DIST_TOKEN` secret).
- The installer here maps a load name + version to that release asset.

---

## 9. Contribution model (per repo)

- **ArrowTDS / ArrowFEBE / ArrowTTC**: git-flow — branch off `develop`, PR into
  `develop`. A pre-commit `clang-format` hook reformats and restages C sources.
- **ArrowDRDA**: `main`-only, no CI yet — branch off `main`, PR into `main`;
  verify locally (`-Werror` build + `ctest`).
- **This repo** (`arpe-io/adbc-drivers`): git-flow, PR into `develop`; see
  [CONTRIBUTING.md](CONTRIBUTING.md).

C changes must build clean under `-Werror` and keep `ctest` green. Parser and
option changes carry pure-C unit tests (the C-unit-test build compiles the driver
sources directly; the `.so`/validation suite is the end-to-end gate).

---

## 10. Per-driver quick reference

| | ArrowTDS | ArrowFEBE | ArrowTTC | ArrowDRDA |
|---|---|---|---|---|
| Database | SQL Server | PostgreSQL | Oracle | IBM Db2 |
| Load name | `arrowtds` | `arrowfebe` | `arrowttc` | `arrowdrda` |
| Library | `arrowtds_adbc_driver` | `arrowfebe_adbc_driver` | `arrowttc_adbc_driver` | `arrowdrda_adbc_driver` |
| Named entrypoint | `AdbcDriverArrowTDSInit` | `AdbcDriverArrowFEBEInit` | `AdbcDriverArrowTTCInit` | `AdbcDriverArrowDRDAInit` |
| URI schemes | `sqlserver`/`mssql`/`arrowtds` | `postgresql`/`postgres`/`arrowfebe` | `oracle`/`arrowttc` | `db2`/`arrowdrda` |
| URI path = | instance | database | service name | database |
| Default port | 1433 | 5432 | 1521 | 50000 |

> **Registry note:** `registry.json` and the README currently list only the
> published drivers (`arrowtds`, `arrowfebe`). `arrowttc` and `arrowdrda` join
> the installer once their release CI cross-publishes binaries here.
