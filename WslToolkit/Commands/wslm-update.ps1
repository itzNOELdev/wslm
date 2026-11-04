# Returns the non-empty, NUL-free output lines of a wsl.exe call.
function Get-WslmInfoLines {
    param(
        [Parameter(Mandatory)]
        [string[]]$WslArgs
    )

    $output = & $global:WslToolkitWslExe @WslArgs 2>&1

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

    foreach ($line in $Lines) {
        if ($line -match '^([^:]+):\s*(.*)$') {
            [pscustomobject]@{
                Section = $Section
                Setting = $Matches[1].Trim()
                Value   = $Matches[2].Trim()
            }
        }
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
        Show-WslHelp `
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
        $statusLines  = @(Get-WslmInfoLines -WslArgs @('--status'))
        $versionLines = @(Get-WslmInfoLines -WslArgs @('--version'))

        $rows = @(
            ConvertTo-WslmInfoRows -Lines $statusLines -Section 'Status'
            ConvertTo-WslmInfoRows -Lines $versionLines -Section 'Version'
        )

        if (-not $rows.Count) {
            # Unexpected format: show the raw text instead of nothing.
            $statusLines
            $versionLines
            return
        }

        Write-Host ''

        Write-WslTable `
            -Rows $rows `
            -Columns @('Section', 'Setting', 'Value') `
            -GroupColumn 'Section'

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

    Invoke-Wsl -WslArgs $updateArgs

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