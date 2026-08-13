@{
    # Enforced at Error AND Warning severity in CI (see .github/workflows/powershell-lint.yml).
    # The two exclusions below are deliberate, not oversights - see CONTRIBUTING.md
    # "Lint rule exceptions" for the reasoning behind each one.
    ExcludeRules = @(
        # PSAvoidUsingWriteHost: this project's scripts are run interactively by
        # an admin during install/troubleshooting (Setup-TorService.ps1 even
        # pauses for a keypress when run standalone). Write-Host is the correct
        # tool for that - not a module meant to be composed in a pipeline, where
        # this rule's concern (breaking output capture/redirection) would apply.
        'PSAvoidUsingWriteHost',

        # PSUseShouldProcessForStateChangingFunctions: flags Save-State in
        # Watchdog-TorAutoBridge.ps1 for its verb. It's a private, internal
        # helper that persists the watchdog's own tracking file - not a public
        # cmdlet a user would run with -WhatIf/-Confirm expectations.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
