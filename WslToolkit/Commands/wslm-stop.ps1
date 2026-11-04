function Invoke-WslmStop {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslHelp `
            -Command 'wslm stop' `
            -Usage 'wslm stop <Distro|#> [<Distro|#> ...] | wslm stop --all' `
            -Description 'Stop one or more WSL distributions (by name or number from wslm list), or shut down all of WSL.'
        return
    }

    if (-not $tokens.Count) {
        throw 'Usage: wslm stop <Distro|#> [<Distro|#> ...] or wslm stop --all'
    }

    if ($tokens -contains '--all') {
        if ($tokens.Count -ne 1) {
            throw '--all cannot be combined with a distribution name.'
        }

        Invoke-Wsl -WslArgs @('--shutdown') -Quiet
        Write-Host 'WSL has been shut down. All distributions are stopped.' -ForegroundColor Green
        return
    }

    foreach ($token in $tokens) {
        if ($token.StartsWith('--')) {
            throw "Unknown option: $token"
        }
    }

    # Resolve everything first, so a typo stops nothing.
    $rows = @(Get-WslRows)
    $targets = [System.Collections.Generic.List[string]]::new()

    foreach ($token in $tokens) {
        $name = Resolve-WslDistro -Name $token -Rows $rows

        if (-not $targets.Contains($name)) {
            $targets.Add($name)
        }
    }

    $failed = 0

    foreach ($name in $targets) {
        $state = ($rows | Where-Object Name -eq $name | Select-Object -First 1).State

        if ($state -eq 'Stopped') {
            Write-Host "$name is already stopped." -ForegroundColor DarkGray
            continue
        }

        try {
            Invoke-Wsl -WslArgs @('--terminate', $name) -Quiet
            Write-Host "Stopped $name" -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Warning "Could not stop '$name': $_"
        }
    }

    if ($failed) {
        throw "Could not stop $failed of $($targets.Count) distribution(s)."
    }
}