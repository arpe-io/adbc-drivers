<!-- Target this PR at `develop` (see CONTRIBUTING.md). -->

## What

<!-- What does this change do? -->

## Why

<!-- What problem does it solve, or what does it improve? -->

## Testing

<!-- How did you verify it? Tick what applies. -->

- [ ] `sh -n install.sh` passes
- [ ] `shellcheck -S warning -s sh install.sh` is clean
- [ ] `Invoke-ScriptAnalyzer -Path ./install.ps1 -Settings ./.github/PSScriptAnalyzerSettings.psd1` is clean
- [ ] Ran the affected command(s) end-to-end (install / list / installed / uninstall)

## Checklist

- [ ] `install.sh` and `install.ps1` kept in sync (if applicable)
- [ ] `README.md` updated (if flags/behavior changed)
