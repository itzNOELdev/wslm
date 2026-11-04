# Best effort: wsl --import always logs in as root. Find the regular user
# (UID 1000) inside the restored distro and record it in /etc/wsl.conf,
# which is WSL's own setting for the default user.
function Set-WslmRestoredUser {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$User
    )

    try {
        if (-not $User) {
            $passwd = (& $global:WslmWslExePath --distribution $Name --user root --exec getent passwd 1000 2>$null | Out-String).Trim()

            if ($passwd -match '^([^:\s]+):') {
                $User = $Matches[1]
            }
        }

        if (-not $User) {
            Write-Warning "Could not find a regular user in '$Name'; it will log in as root. Use --user <name> to set one."
            return
        }

        if ($User -eq 'root') {
            return
        }

        $conf = (& $global:WslmWslExePath --distribution $Name --user root --exec cat /etc/wsl.conf 2>$null | Out-String)

        if ($LASTEXITCODE -ne 0) {
            $conf = ''
        }

        if ($conf -match '(?m)^\s*\[user\]') {
            Write-Warning "/etc/wsl.conf in '$Name' already has a [user] section, so the default user was left as it is."
            return
        }

        "`n[user]`ndefault=$User" |
            & $global:WslmWslExePath --distribution $Name --user root --exec tee -a /etc/wsl.conf |
            Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw 'Could not write /etc/wsl.conf.'
        }

        # The pipe adds a Windows line ending; remove it.
        & $global:WslmWslExePath --distribution $Name --user root --exec sed -i 's/\r$//' /etc/wsl.conf | Out-Null

        # The setting is read when the distribution starts.
        & $global:WslmWslExePath --terminate $Name | Out-Null

        Write-Host "Default user set to: $User" -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not set the default user: $_"
    }
}

function Invoke-WslmRestore {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslmCommandHelp `
            -Command 'wslm restore' `
            -Usage 'wslm restore <#|file> [--name <New>] [--path <folder>] [--replace] [--user <User>] [--no-user-fix] [--out <folder>] | wslm restore list [--out <folder>]' `
            -Description "Restore a WSL 2 distribution from a backup (see wslm backup list) with wsl --import. Without --name it comes back under its original name. Default install folder: $HOME\WSL\<Name>. Use -- before a backup name that matches 'list'."
        return
    }

    $newName = $null
    $installPath = $null
    $folderOverride = $null
    $user = $null
    $replace = $false
    $noUserFix = $false
    $literal = $false
    $seen = @{}
    $words = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = [string]$tokens[$i]

        # Everything after '--' is positional, never an option.
        if ($literal) {
            $words.Add($token)
            continue
        }

        if ($token -eq '--') {
            $literal = $true
            continue
        }

        switch ($token) {
            { $_ -in @('--name', '--path', '--out', '--user') } {
                Assert-WslmOptionOnce -Seen $seen -Option $token

                if (($i + 1) -ge $tokens.Count -or ([string]$tokens[$i + 1]).StartsWith('--')) {
                    throw "Provide a value after $token."
                }

                $value = [string]$tokens[++$i]

                switch ($token) {
                    '--name' { $newName = $value }
                    '--path' { $installPath = $value }
                    '--out'  { $folderOverride = $value }
                    '--user' { $user = $value }
                }
            }
            '--replace'     { $replace = $true }
            '--no-user-fix' { $noUserFix = $true }
            default {
                if ($token.StartsWith('--')) {
                    throw "Unknown option: $token"
                }

                $words.Add($token)
            }
        }
    }

    $folder = Get-WslmBackupFolder -Path $folderOverride

    # ---------------------------------------------------------- list
    if (-not $literal -and $words.Count -eq 1 -and $words[0] -eq 'list') {
        if ($null -ne $newName)    { throw "--name cannot be used with 'wslm restore list'." }
        if ($null -ne $installPath) { throw "--path cannot be used with 'wslm restore list'." }
        if ($replace)              { throw "--replace cannot be used with 'wslm restore list'." }
        if ($null -ne $user)       { throw "--user cannot be used with 'wslm restore list'." }
        if ($noUserFix)            { throw "--no-user-fix cannot be used with 'wslm restore list'." }

        Show-WslmBackupList -Folder $folder
        return
    }

    if ($words.Count -ne 1) {
        throw 'Usage: wslm restore <#|file> [--name <New>] [--path <folder>] [--replace] [--user <User>] [--no-user-fix] [--out <folder>] | wslm restore list [--out <folder>]'
    }

    if ($user -and $user -notmatch '^[a-z_][a-z0-9_-]*\$?$') {
        throw "'$user' is not a valid Linux user name."
    }

    $backups = @(Get-WslmBackup -Folder $folder)
    $backup = Resolve-WslmBackup -Token $words[0] -Backups $backups

    $name = if ($newName) { $newName }
            elseif ($backup.Distro -ne '?') { $backup.Distro }
            else { throw 'Cannot tell which distribution this backup came from. Use --name <Name>.' }

    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "'$name' is not a valid distribution name (letters, digits, '.', '_' and '-' only)."
    }

    $installed = @(Get-WslmInstalledName)
    $exists = $installed -contains $name

    if ($exists -and -not $replace) {
        throw "'$name' is already installed. Use --name <New> to restore a copy, or --replace to overwrite it."
    }

    if ($replace -and -not $exists) {
        Write-Host "'$name' is not installed, so there is nothing to replace. Restoring normally." -ForegroundColor DarkGray
        $replace = $false
    }

    if (-not $installPath) {
        $installPath = Join-Path (Join-Path $HOME 'WSL') $name
    }

    $pathInUse = {
        (Test-Path -LiteralPath $installPath) -and
        (@(Get-ChildItem -LiteralPath $installPath -Force -ErrorAction SilentlyContinue).Count -gt 0)
    }

    if (-not $replace -and (& $pathInUse)) {
        throw "The install folder '$installPath' is not empty. Use --path <folder> to choose another."
    }

    # ------------------------------------------------------- replace
    if ($replace) {
        Write-Host "`nThis permanently deletes the current '$name' and replaces it with:" -ForegroundColor Red
        Write-Host "  $($backup.FileName)  (backed up $($backup.BackedText))"

        $answer = Read-Host "`nType YES to confirm"

        if ($answer -cne 'YES') {
            Write-Host 'Cancelled.'
            return
        }

        $safety = Read-Host "Back up the current '$name' first? [Y/n]"

        if ($safety -notmatch '^(n|no)$') {
            Write-Host "Backing up current $name ... (this can take a few minutes)" -ForegroundColor Cyan
            $safetyFile = Export-WslmBackup -Name $name -Folder $folder
            Write-Host "Safety backup saved: $($safetyFile.FullName)" -ForegroundColor Green
        }

        Invoke-WslmWslExe -WslArgs @('--unregister', $name) -Quiet

        if (& $pathInUse) {
            throw "The old '$name' was removed, but the install folder '$installPath' is not empty. Your backup is untouched; run again with --path <folder>."
        }
    }

    # -------------------------------------------------------- import
    if (-not (Test-Path -LiteralPath $installPath)) {
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
    }

    $importArgs = @('--import', $name, $installPath, $backup.Path)

    if ($backup.Format -eq 'vhdx') {
        $importArgs += '--vhd'
    }

    Write-Host "Restoring $name from $($backup.FileName) ... (this can take a few minutes)" -ForegroundColor Cyan

    Invoke-WslmWslExe -WslArgs $importArgs -Quiet -Activity "Importing $name"

    Write-Host "Restored $name  ->  $installPath" -ForegroundColor Green

    if (-not $noUserFix) {
        Set-WslmRestoredUser -Name $name -User $user
    }

    Write-Host "Open it with: wslm shell $name`n" -ForegroundColor DarkGray
}