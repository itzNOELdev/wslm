function Invoke-WslmBackup {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslmCommandHelp `
            -Command 'wslm backup' `
            -Usage 'wslm backup <Distro|#> [...] | --all [--vhd] [--live] [--out <folder>] | list [--out <folder>] | delete <#|file> [--force] [--out <folder>] | prune --keep <N> [--force] [--out <folder>]' `
            -Description "Back up WSL 2 distributions with wsl --export into a backup folder (default: $global:WslmBackupDir). A running distribution is stopped first unless --live is given. Use -- before a distro name that matches a mode word (list, delete, prune)."
        return
    }

    $folderOverride = $null
    $all = $false
    $vhd = $false
    $live = $false
    $force = $false
    $keep = $null
    $literal = $false
    $seen = @{}
    $words = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = [string]$tokens[$i]

        # Everything after '--' is positional, never an option or mode word.
        if ($literal) {
            $words.Add($token)
            continue
        }

        if ($token -eq '--') {
            $literal = $true
            continue
        }

        switch ($token) {
            '--out' {
                Assert-WslmOptionOnce -Seen $seen -Option $token

                if (($i + 1) -ge $tokens.Count -or ([string]$tokens[$i + 1]).StartsWith('--')) {
                    throw 'Provide a folder after --out.'
                }

                $folderOverride = [string]$tokens[++$i]
            }
            '--keep' {
                Assert-WslmOptionOnce -Seen $seen -Option $token

                if (($i + 1) -ge $tokens.Count) { throw 'Provide a number after --keep.' }

                $parsed = 0

                if (-not [int]::TryParse([string]$tokens[++$i], [ref]$parsed) -or $parsed -lt 1) {
                    throw '--keep needs a whole number of 1 or more.'
                }

                $keep = $parsed
            }
            '--all'   { $all = $true }
            '--vhd'   { $vhd = $true }
            '--live'  { $live = $true }
            '--force' { $force = $true }
            default {
                if ($token.StartsWith('--')) {
                    throw "Unknown option: $token"
                }

                $words.Add($token)
            }
        }
    }

    $mode = 'create'
    $rest = @($words)

    if (-not $literal -and $words.Count -and $words[0] -in @('list', 'delete', 'prune')) {
        $mode = $words[0]
        $rest = @($words | Select-Object -Skip 1)
    }

    # Reject options that do not belong to the chosen mode.
    $allowed = switch ($mode) {
        'create' { @('all', 'vhd', 'live') }
        'list'   { @() }
        'delete' { @('force') }
        'prune'  { @('keep', 'force') }
    }

    $used = [ordered]@{
        all = $all; vhd = $vhd; live = $live; force = $force; keep = ($null -ne $keep)
    }

    foreach ($key in $used.Keys) {
        if ($used[$key] -and $key -notin $allowed) {
            throw "--$key cannot be used with 'wslm backup $mode'."
        }
    }

    $folder = Get-WslmBackupFolder -Path $folderOverride

    # ---------------------------------------------------------- list
    if ($mode -eq 'list') {
        if ($rest.Count) { throw 'Usage: wslm backup list [--out <folder>]' }

        Show-WslmBackupList -Folder $folder
        return
    }

    # -------------------------------------------------------- delete
    if ($mode -eq 'delete') {
        if (-not $rest.Count) { throw 'Usage: wslm backup delete <#|file> [...] [--force] [--out <folder>]' }

        $backups = @(Get-WslmBackup -Folder $folder)
        $targets = [System.Collections.Generic.List[object]]::new()

        foreach ($token in $rest) {
            $backup = Resolve-WslmBackup -Token $token -Backups $backups

            if (-not ($targets | Where-Object Path -eq $backup.Path)) {
                $targets.Add($backup)
            }
        }

        Write-Host "`nThe following backups will be permanently deleted:" -ForegroundColor Red

        foreach ($target in $targets) {
            Write-Host "  $($target.FileName)  ($($target.Size))"
        }

        if (-not $force) {
            $answer = Read-Host "`nType YES to confirm"

            if ($answer -cne 'YES') {
                Write-Host 'Cancelled.'
                return
            }
        }

        foreach ($target in $targets) {
            Remove-Item -LiteralPath $target.Path -Force
            Write-Host "Deleted $($target.FileName)" -ForegroundColor Green
        }

        return
    }

    # --------------------------------------------------------- prune
    if ($mode -eq 'prune') {
        if ($rest.Count) { throw 'Usage: wslm backup prune --keep <N> [--force] [--out <folder>]' }
        if ($null -eq $keep) { throw 'Usage: wslm backup prune --keep <N> [--force] [--out <folder>]' }

        $backups = @(Get-WslmBackup -Folder $folder | Where-Object Distro -ne '?')

        $doomed = @(
            $backups |
                Group-Object Distro |
                ForEach-Object {
                    $_.Group |
                        Sort-Object Backed -Descending |
                        Select-Object -Skip $keep
                }
        )

        if (-not $doomed.Count) {
            Write-Host "Nothing to prune. Every distribution has $keep or fewer backups."
            return
        }

        $freed = ($doomed | Measure-Object -Property Bytes -Sum).Sum

        Write-Host "`nKeeping the newest $keep backup(s) per distribution. These will be permanently deleted:" -ForegroundColor Red

        foreach ($item in $doomed) {
            Write-Host "  $($item.FileName)  ($($item.Size))"
        }

        Write-Host "`nThis frees $(Format-WslmSize $freed)."

        if (-not $force) {
            $answer = Read-Host "`nType YES to confirm"

            if ($answer -cne 'YES') {
                Write-Host 'Cancelled.'
                return
            }
        }

        foreach ($item in $doomed) {
            Remove-Item -LiteralPath $item.Path -Force
        }

        Write-Host "Deleted $($doomed.Count) backup(s)." -ForegroundColor Green
        return
    }

    # -------------------------------------------------------- create
    $rows = @(Get-WslmDistro)

    if ($all) {
        if ($rest.Count) { throw '--all cannot be combined with a distribution name.' }

        if (-not $rows.Count) {
            Write-Host 'No WSL 2 distributions are installed.'
            return
        }

        $targets = @($rows.Name)
    }
    else {
        if (-not $rest.Count) {
            throw 'Usage: wslm backup <Distro|#> [...] [--vhd] [--live] [--out <folder>]'
        }

        # Resolve everything first, so a typo backs up nothing.
        $resolved = [System.Collections.Generic.List[string]]::new()

        foreach ($token in $rest) {
            $name = Resolve-WslmDistro -Name $token -Rows $rows

            if (-not $resolved.Contains($name)) {
                $resolved.Add($name)
            }
        }

        $targets = $resolved.ToArray()
    }

    $failed = 0

    foreach ($name in $targets) {
        Write-Host "Backing up $name ... (this can take a few minutes)" -ForegroundColor Cyan

        try {
            $file = Export-WslmBackup -Name $name -Folder $folder -Vhd:$vhd -Live:$live
            Write-Host "Backed up $name  ->  $($file.FullName)  ($(Format-WslmSize $file.Length))" -ForegroundColor Green
        }
        catch {
            $failed++
            Write-Warning "Could not back up '$name': $_"
        }
    }

    if ($failed) {
        throw "Backed up $($targets.Count - $failed) of $($targets.Count) distribution(s); $failed failed."
    }
}