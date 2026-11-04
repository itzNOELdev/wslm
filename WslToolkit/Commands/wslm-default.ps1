function Invoke-WslmDefault {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslHelp `
            -Command 'wslm default' `
            -Usage 'wslm default [<Distro|#>] [--help]' `
            -Description 'Show the default WSL distribution, or set it by name or number from wslm list.'
        return
    }

    foreach ($token in $tokens) {
        if ($token.StartsWith('--')) {
            throw "Unknown option: $token"
        }
    }

    if ($tokens.Count -gt 1) {
        throw 'Usage: wslm default [<Distro|#>]'
    }

    $rows = @(Get-WslRows)
    $current = $rows | Where-Object Default | Select-Object -First 1

    # No argument: show the current default.
    if ($tokens.Count -eq 0) {
        if ($current) {
            Write-Host "Default distribution: $($current.Name)  (#$($current.Number), $($current.State))" -ForegroundColor Green
        }
        else {
            Write-Host 'No default distribution found.'
        }

        return
    }

    # One argument: set the default.
    $name = Resolve-WslDistro -Name $tokens[0] -Rows $rows

    if ($current -and $current.Name -eq $name) {
        Write-Host "$name is already the default distribution." -ForegroundColor DarkGray
        return
    }

    Invoke-Wsl -WslArgs @('--set-default', $name) -Quiet

    if ($current) {
        Write-Host "Default distribution changed: $($current.Name) -> $name" -ForegroundColor Green
    }
    else {
        Write-Host "Default distribution set to: $name" -ForegroundColor Green
    }
}