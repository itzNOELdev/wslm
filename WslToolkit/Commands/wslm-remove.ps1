function Invoke-WslmRemove {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslmCommandHelp `
            -Command 'wslm remove' `
            -Usage 'wslm remove <Distro|#> [<Distro|#> ...] [--force] | wslm remove --all [--force]' `
            -Description 'Unregister and permanently delete WSL 2 distributions (by name or number from wslm list).'
        return
    }

    $force = $tokens -contains '--force'
    $all = $tokens -contains '--all'

    foreach ($token in $tokens) {
        if (([string]$token).StartsWith('--') -and $token -notin @('--force', '--all')) {
            throw "Unknown option: $token"
        }
    }

    $names = @(
        $tokens | Where-Object {
            $_ -notin @('--force', '--all')
        }
    )

    if ($all -and $names.Count -gt 0) {
        throw '--all cannot be combined with a distribution name.'
    }

    if (-not $all -and $names.Count -eq 0) {
        throw 'Usage: wslm remove <Distro|#> [<Distro|#> ...] [--force] | wslm remove --all [--force]'
    }

    $rows = @(Get-WslmDistro)

    if ($all) {
        if (-not $rows.Count) {
            Write-Host 'No WSL 2 distributions are installed.'
            return
        }

        $targets = @($rows.Name)
    }
    else {
        # Resolve everything first, so a typo deletes nothing.
        $resolved = [System.Collections.Generic.List[string]]::new()

        foreach ($name in $names) {
            $target = Resolve-WslmDistro -Name $name -Rows $rows

            if (-not $resolved.Contains($target)) {
                $resolved.Add($target)
            }
        }

        $targets = $resolved.ToArray()
    }

    if (-not $force) {
        if ($targets.Count -eq 1 -and -not $all) {
            $answer = Read-Host "Permanently delete '$($targets[0])'? Type YES to confirm"
            $expected = 'YES'
        }
        else {
            Write-Host "`nThe following distributions will be permanently deleted:" -ForegroundColor Red

            foreach ($target in $targets) {
                $number = ($rows | Where-Object Name -eq $target | Select-Object -First 1).Number
                Write-Host ("  {0,2}. {1}" -f $number, $target)
            }

            $expected = if ($all) { 'REMOVE ALL' } else { 'YES' }
            $answer = Read-Host "`nType $expected to confirm"
        }

        if ($answer -cne $expected) {
            Write-Host 'Cancelled.'
            return
        }
    }

    $failed = 0

    foreach ($target in $targets) {
        Write-Host "Removing $target ..." -ForegroundColor Yellow

        try {
            Invoke-WslmWslExe -WslArgs @('--unregister', $target) -Quiet
            Write-Host "Removed $target" -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Warning "Could not remove '$target': $_"
        }
    }

    if ($failed) {
        throw "Removed $($targets.Count - $failed) of $($targets.Count) distribution(s); $failed failed."
    }

    Write-Host "Removed $($targets.Count) distribution(s)." -ForegroundColor Green
}