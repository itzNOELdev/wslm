# Starts a distribution without opening a shell. WSL stops a distribution
# shortly after its last process ends, so a hidden keep-alive process is
# left running inside it. 'wslm stop' ends it.
function Start-WslmBackground {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$User
    )

    $wslArgs = @('--distribution', $Name)

    if ($User) {
        $wslArgs += @('--user', $User)
    }

    $wslArgs += @('--exec', 'tail', '-f', '/dev/null')

    Start-Process `
        -FilePath $global:WslToolkitWslExe `
        -ArgumentList $wslArgs `
        -WindowStyle Hidden | Out-Null

    # Wait (up to ~10 seconds) until WSL reports it as running.
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500

        $row = Get-WslRows | Where-Object Name -eq $Name | Select-Object -First 1

        if ($row -and $row.State -eq 'Running') {
            return $true
        }
    }

    return $false
}

function Invoke-WslmStart {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslHelp `
            -Command 'wslm start' `
            -Usage 'wslm start <Distro|#> [--user <User>] | wslm start <Distro|#> [...] --background | wslm start --all' `
            -Description 'Open a shell in a distribution (by name or number from wslm list). With --background, start it without a shell and keep it running. --all starts every distribution in the background.'
        return
    }

    $user = $null
    $background = $false
    $all = $false
    $names = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = [string]$tokens[$i]

        if ($token -eq '--user') {
            if ($user) {
                throw 'Use --user only once.'
            }

            if (($i + 1) -ge $tokens.Count -or ([string]$tokens[$i + 1]).StartsWith('--')) {
                throw 'Provide a username after --user.'
            }

            $user = [string]$tokens[++$i]
        }
        elseif ($token -eq '--background') {
            $background = $true
        }
        elseif ($token -eq '--all') {
            $all = $true
        }
        elseif ($token.StartsWith('--')) {
            throw "Unknown option: $token"
        }
        else {
            $names.Add($token)
        }
    }

    $rows = @(Get-WslRows)

    if ($all) {
        if ($names.Count -or $user) {
            throw '--all cannot be combined with a distribution name or --user.'
        }

        if (-not $rows.Count) {
            Write-Host 'No distributions are installed.'
            return
        }

        $background = $true
        $targets = @($rows.Name)
    }
    else {
        if (-not $names.Count) {
            throw 'Usage: wslm start <Distro|#> [--user <User>] [--background]'
        }

        if (-not $background -and $names.Count -gt 1) {
            throw 'Only one distribution can be opened at a time. Use --background to start several.'
        }

        # Resolve everything first, so a typo starts nothing.
        $resolved = [System.Collections.Generic.List[string]]::new()

        foreach ($name in $names) {
            $target = Resolve-WslDistro -Name $name -Rows $rows

            if (-not $resolved.Contains($target)) {
                $resolved.Add($target)
            }
        }

        $targets = $resolved.ToArray()
    }

    # Interactive: open a shell. The shell's own exit code (the last command
    # you ran) is not an error, so it is deliberately not checked.
    if (-not $background) {
        $shellArgs = @('--distribution', $targets[0])

        if ($user) {
            $shellArgs += @('--user', $user)
        }

        & $global:WslToolkitWslExe @shellArgs
        return
    }

    # Background: start without a shell and keep running.
    $failed = 0

    foreach ($target in $targets) {
        $state = ($rows | Where-Object Name -eq $target | Select-Object -First 1).State

        if ($state -eq 'Running') {
            Write-Host "$target is already running." -ForegroundColor DarkGray
            continue
        }

        Write-Host "Starting $target ..." -ForegroundColor Cyan

        if (Start-WslmBackground -Name $target -User $user) {
            Write-Host "Started $target in the background. Stop it with: wslm stop $target" -ForegroundColor Green
        }
        else {
            $failed++
            Write-Warning "Could not confirm that '$target' started."
        }
    }

    if ($failed) {
        throw "Could not start $failed of $($targets.Count) distribution(s)."
    }
}