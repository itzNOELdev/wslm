function Invoke-WslmFind {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslHelp `
            -Command 'wslm find' `
            -Usage 'wslm find [--name <text>] [--help]' `
            -Description 'Find distributions available for installation, grouped by family.'
        return
    }

    $filter = $null

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -eq '--name') {
            if ($filter) {
                throw 'Use --name only once.'
            }

            if (($i + 1) -ge $tokens.Count -or $tokens[$i + 1].StartsWith('--')) {
                throw 'Provide a search term after --name.'
            }

            $filter = $tokens[++$i]
        }
        else {
            throw "Unknown argument: $($tokens[$i])"
        }
    }

    $distros = @(Get-WslOnlineDistros)

    if ($filter) {
        $distros = @(
            $distros | Where-Object {
                $_.Name.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $_.FriendlyName.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $_.Family.IndexOf($filter, [StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        )
    }

    if (-not $distros.Count) {
        Write-Host 'No matching distributions found.'
        return
    }

    # Group by family, alphabetically (order inside a group is kept).
    $sorted = @(
        $distros |
            Group-Object Family |
            Sort-Object Name |
            ForEach-Object { $_.Group }
    )

    Write-Host ''

    Write-WslTable `
        -Rows $sorted `
        -Columns @('Family', 'Name', 'FriendlyName') `
        -Headers @('Family', 'Name', 'Friendly Name') `
        -GroupColumn 'Family'

    $familyCount = @($sorted | Select-Object -ExpandProperty Family -Unique).Count

    Write-Host "`n$($sorted.Count) distributions in $familyCount families. Install with: wslm make <Name>`n" -ForegroundColor DarkGray
}