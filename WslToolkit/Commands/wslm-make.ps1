function Invoke-WslmMake {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslHelp `
            -Command 'wslm make' `
            -Usage 'wslm make <Distro> [--no-launch] [--help]' `
            -Description 'Install an available WSL distribution (see wslm find for names).'
        return
    }

    foreach ($token in $tokens) {
        if ($token.StartsWith('--') -and $token -ne '--no-launch') {
            throw "Unknown option: $token"
        }
    }

    $noLaunch = $tokens -contains '--no-launch'
    $names = @($tokens | Where-Object { $_ -ne '--no-launch' })

    if ($names.Count -ne 1) {
        throw 'Usage: wslm make <Distro> [--no-launch]'
    }

    $name = $names[0]

    # Check the name against the online list (and fix its capitalisation).
    # If the list cannot be fetched, try the install anyway.
    $available = @()

    try {
        $available = @(Get-WslOnlineDistros)
    }
    catch {
        Write-Warning "Could not check the online list; trying the install anyway. ($_)"
    }

    if ($available.Count) {
        $match = $available | Where-Object { $_.Name -eq $name } | Select-Object -First 1

        if (-not $match) {
            $similar = @(
                $available |
                    Where-Object {
                        $_.Name.IndexOf($name, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                        $_.FriendlyName.IndexOf($name, [StringComparison]::OrdinalIgnoreCase) -ge 0
                    } |
                    Select-Object -First 5 -ExpandProperty Name
            )

            $hint = if ($similar.Count) {
                " Did you mean: $($similar -join ', ')?"
            }
            else {
                ' Run wslm find to see available distributions.'
            }

            throw "'$name' is not an available distribution.$hint"
        }

        $name = $match.Name
    }

    $alreadyInstalled = $false

    try {
        $alreadyInstalled = Test-WslDistro -Name $name
    }
    catch { }

    if ($alreadyInstalled) {
        Write-Host "$name is already installed. Start it with: wslm start $name" -ForegroundColor DarkGray
        return
    }

    $installArgs = @('--install', '--distribution', $name)

    if ($noLaunch) {
        $installArgs += '--no-launch'
    }

    Write-Host "Installing $name ..." -ForegroundColor Cyan

    Invoke-Wsl -WslArgs $installArgs

    if ($noLaunch) {
        Write-Host "`nInstalled $name. It has not been launched yet; start it with: wslm start $name" -ForegroundColor Green
    }
    else {
        Write-Host "`nInstalled $name." -ForegroundColor Green
    }
}