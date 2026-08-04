@{
    # Curated PSScriptAnalyzer ruleset for install.ps1. We fail CI on any Error or
    # Warning, except three rules that flag intentional CLI patterns:
    #   - PSAvoidUsingWriteHost: Write-Host is how a CLI prints to the console.
    #   - PSUseApprovedVerbs: `Fail` is a deliberate one-word error helper.
    #   - PSUseShouldProcessForStateChangingFunctions: Install/Uninstall here are
    #     top-level commands, not reusable cmdlets, so -WhatIf/-Confirm add nothing.
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseApprovedVerbs',
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
