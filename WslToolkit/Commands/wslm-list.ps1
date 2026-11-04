function Invoke-WslmList {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslmCommandHelp `
            -Command 'wslm list' `
            -Usage 'wslm list [--running | --stopped] [--verbose] [--help]' `
            -Description 'List installed WSL 2 distributions. Numbers can be used instead of names, e.g. wslm stop 2.'
        return
    }

    $allowed = @('--running', '--stopped', '--verbose')

    foreach ($token in $tokens) {
        if ($token -notin $allowed) {
            throw "Unknown argument: $token"
        }
    }

    if (($tokens -contains '--running') -and ($tokens -contains '--stopped')) {
        throw 'Choose either --running or --stopped, not both.'
    }

    $rows = @(Get-WslmDistro)

    # Numbers come from the full list, so they stay the same when filtering.
    if ($tokens -contains '--running') {
        $rows = @($rows | Where-Object State -eq 'Running')
    }
    elseif ($tokens -contains '--stopped') {
        $rows = @($rows | Where-Object State -eq 'Stopped')
    }

    if (-not $rows.Count) {
        Write-Host 'No matching distributions found.'
        return
    }

    $view = @(
        foreach ($row in $rows) {
            [pscustomobject]@{
                Number  = $row.Number
                Name    = $row.Name
                State   = $row.State
                Version = "WSL $($row.Version)"
                Default = if ($row.Default) { '*' } else { '' }
            }
        }
    )

    if ($tokens -contains '--verbose') {
        $columns = @('Number', 'Name', 'State', 'Version', 'Default')
        $headers = @('#', 'Name', 'State', 'Version', 'Default')
    }
    else {
        $columns = @('Number', 'Name', 'State', 'Default')
        $headers = @('#', 'Name', 'State', 'Default')
    }

    Write-Host ''

    Write-WslmTable `
        -Rows $view `
        -Columns $columns `
        -Headers $headers `
        -CellColor {
            param($column, $value)

            switch ($column) {
                'Number'  { 'DarkGray' }
                'State'   { if ($value -eq 'Running') { 'Green' } else { 'DarkGray' } }
                'Default' { 'Cyan' }
            }
        }

    $running = @($rows | Where-Object State -eq 'Running').Count

    Write-Host "`n$($rows.Count) distributions, $running running. * = default`n" -ForegroundColor DarkGray
}