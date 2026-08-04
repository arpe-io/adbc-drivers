# Contributing

Thanks for your interest in improving the Arpeio ADBC installers! This repository
hosts the **installers** (`install.sh`, `install.ps1`), the driver **registry**
(`registry.json`), and the docs. The driver *sources* are proprietary and live in
private repositories, so contributions here focus on:

- the install/uninstall/list scripts and their portability,
- the registry and driver metadata,
- documentation and examples.

## Branching model (git-flow)

| Branch | Purpose |
|---|---|
| `main` | Stable, released code. Every install one-liner points at `main`, so it must always work. Tagged for releases (`vX.Y.Z`). |
| `develop` | Integration branch for day-to-day work. **Target your PRs here.** |
| `release/*` | Short-lived branches cut from `develop` to stabilise a release, then merged into `main` and tagged. |

> Driver *binaries* are published under their own `<driver>-v<version>` releases
> (e.g. `arrowtds-v0.5.19`); those are separate from the `vX.Y.Z` installer tags.

## Making a change

1. **Fork** the repository and clone your fork.
2. Create a branch off `develop`:
   ```sh
   git switch develop
   git switch -c my-change
   ```
3. Make your change and run the local checks (below).
4. Open a **pull request into `develop`** and fill in the template.

External contributors work from a fork — you don't need push access to any branch.

## Local checks

The same checks run in CI (`.github/workflows/lint.yml`); please run them before
opening a PR.

**`install.sh`** — POSIX syntax + shellcheck:
```sh
sh -n install.sh
shellcheck -S warning -s sh install.sh
```

**`install.ps1`** — PSScriptAnalyzer with the repo ruleset:
```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser  # once
Invoke-ScriptAnalyzer -Path ./install.ps1 -Settings ./.github/PSScriptAnalyzerSettings.psd1
```

Keep the two installers in sync: a change to one usually needs the equivalent in
the other, and the same in the `README.md` options table.

## Releasing (maintainers)

1. Cut `release/vX.Y.Z` from `develop`, finalise the changelog, bump the installer
   version badge in `README.md`.
2. Merge into `main`, then tag and publish a GitHub Release:
   ```sh
   git tag -a vX.Y.Z -m "Installer vX.Y.Z: <summary>"
   git push origin vX.Y.Z
   gh release create vX.Y.Z --title "vX.Y.Z — <summary>" --verify-tag --notes "..."
   ```
3. Merge `main` back into `develop`.

## Licence

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE) that covers this repository.
