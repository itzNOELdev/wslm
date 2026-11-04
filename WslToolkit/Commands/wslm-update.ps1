# Returns the non-empty, NUL-free output lines of a wsl.exe call.
function Get-WslmInfoLines {
    param(
        [Parameter(Mandatory)]
        [string[]]$WslArgs
    )

    $output = & $global:WslmWslExePath @WslArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed: wsl $($WslArgs -join ' ')"
    }

    foreach ($entry in $output) {
        $line = ([string]$entry -replace "`0", '').Trim()

        if ($line) {
            $line
        }
    }
}

# Turns "Label: value" lines into rows. Splitting on the colon works in any
# language. Lines without a colon are returned separately as notes.
function ConvertTo-WslmInfoRows {
    param(
        [string[]]$Lines,
        [string]$Section
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $notes = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $Lines) {
        if ($line -match '^([^:]+):\s*(.*)$') {
            $rows.Add([pscustomobject]@{
                Section = $Section
                Setting = $Matches[1].Trim()
                Value   = $Matches[2].Trim()
            })
        }
        else {
            $notes.Add($line)
        }
    }

    return [pscustomobject]@{
        Rows  = $rows.ToArray()
        Notes = $notes.ToArray()
    }
}

# The first line of 'wsl --version' is the WSL version. Returns $null if
# it cannot be read (for example on very old WSL builds).
function Get-WslmWslVersion {
    try {
        $first = @(Get-WslmInfoLines -WslArgs @('--version')) | Select-Object -First 1

        if ($first -match '^[^:]+:\s*(.+)$') {
            return $Matches[1].Trim()
        }
    }
    catch { }

    return $null
}

function Invoke-WslmUpdate {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslmCommandHelp `
            -Command 'wslm update' `
            -Usage 'wslm update [--status | --web-download] [--help]' `
            -Description 'Update WSL, or show its version and status.'
        return
    }

    if ($tokens.Count -gt 1) {
        throw 'Choose only one option: --status or --web-download.'
    }

    # --status: show everything in one table.
    if ($tokens -contains '--status') {
        $statusLines = @()

        try {
            $statusLines = @(Get-WslmInfoLines -WslArgs @('--status'))
        }
        catch {
            Write-Warning "Could not read 'wsl --status': $_"
        }

        $versionLines = @(Get-WslmInfoLines -WslArgs @('--version'))

        $status = ConvertTo-WslmInfoRows -Lines $statusLines -Section 'Status'
        $version = ConvertTo-WslmInfoRows -Lines $versionLines -Section 'Version'

        $rows = @($status.Rows) + @($version.Rows)
        $notes = @($status.Notes) + @($version.Notes)

        if (-not $rows.Count) {
            # Unexpected format: show the raw text instead of nothing.
            $statusLines
            $versionLines
            return
        }

        Write-Host ''

        Write-WslmTable `
            -Rows $rows `
            -Columns @('Section', 'Setting', 'Value') `
            -GroupColumn 'Section'

        if ($notes.Count) {
            Write-Host "`nNotes:" -ForegroundColor DarkGray

            foreach ($note in $notes) {
                Write-Host "  $note" -ForegroundColor DarkGray
            }
        }

        Write-Host ''
        return
    }

    $updateArgs = @('--update')

    if ($tokens -contains '--web-download') {
        $updateArgs += '--web-download'
    }
    elseif ($tokens.Count -eq 1) {
        throw "Unknown option: $($tokens[0])"
    }

    $before = Get-WslmWslVersion

    Invoke-WslmWslExe -WslArgs $updateArgs

    $after = Get-WslmWslVersion

    if ($before -and $after) {
        if ($before -eq $after) {
            Write-Host "`nWSL is up to date ($after)." -ForegroundColor Green
        }
        else {
            Write-Host "`nWSL updated: $before -> $after" -ForegroundColor Green
        }
    }
    else {
        Write-Host "`nUpdate completed." -ForegroundColor Green
    }
}