# ============================================================
# WSL TOOLKIT - HELPERS
# Shared helper functions
# ============================================================

$global:WslmWslExePath = 'wsl.exe'

function Show-WslmCommandHelp {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter(Mandatory)]
        [string]$Usage,

        [string]$Description = ''
    )

    Write-Host "`n$Command" -ForegroundColor Cyan

    if ($Description) {
        Write-Host $Description
    }

    Write-Host "`nUsage: $Usage`n"
}

function Invoke-WslmWslExe {
    param(
        [Parameter(Mandatory)]
        [string[]]$WslArgs,

        # Hide wsl.exe's own output; it is still included in any error.
        [switch]$Quiet
    )

    if ($Quiet) {
        $output = & $global:WslmWslExePath @WslArgs 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            $text = (@($output | ForEach-Object { ([string]$_ -replace "`0", '').Trim() }) -join ' ').Trim()
            throw "WSL command failed with exit code $exitCode. $text".Trim()
        }

        return
    }

    & $global:WslmWslExePath @WslArgs
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "WSL command failed with exit code $exitCode."
    }
}

function Get-WslmDistro {
    $output = & $global:WslmWslExePath --list --verbose 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw 'Unable to retrieve installed WSL distributions.'
    }

    $parsed = [System.Collections.Generic.List[object]]::new()

    foreach ($entry in $output) {
        # WSL output may contain NUL characters.
        $line = ([string]$entry -replace "`0", '').Trim()

        # [*] NAME STATE VERSION  - the header never matches because it
        # does not end in a number, so this works in any language.
        # Only WSL 2 and newer are supported; WSL 1 rows are ignored.
        if ($line -match '^(\*)?\s*(.+?)\s+(\S+)\s+(\d+)$') {
            $version = [int]$Matches[4]

            if ($version -gt 1) {
                $parsed.Add([pscustomobject]@{
                    Default = [bool]$Matches[1]
                    Name    = $Matches[2].Trim()
                    Raw     = $Matches[3]
                    Version = $version
                })
            }
        }
    }

    # English output already says Running/Stopped. On other languages the
    # word is translated, so ask WSL which distributions are running.
    $runningNames = $null

    $rows = foreach ($p in $parsed) {
        $state = $p.Raw

        if ($state -notin @('Running', 'Stopped')) {
            if ($null -eq $runningNames) {
                $runningNames = @(
                    & $global:WslmWslExePath --list --running --quiet 2>&1 |
                        ForEach-Object { ([string]$_ -replace "`0", '').Trim() }
                )
            }

            $state = if ($runningNames -contains $p.Name) { 'Running' } else { 'Stopped' }
        }

        [pscustomobject]@{
            Default = $p.Default
            Name    = $p.Name
            State   = $state
            Version = $p.Version
        }
    }

    # Sorted by name so the numbers stay stable (they do not change when
    # the default distro or a running state changes).
    $n = 0

    return @(
        $rows | Sort-Object Name | ForEach-Object {
            $n++

            [pscustomobject]@{
                Number  = $n
                Default = $_.Default
                Name    = $_.Name
                State   = $_.State
                Version = $_.Version
            }
        }
    )
}

function Assert-WslmOptionOnce {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Seen,

        [Parameter(Mandatory)]
        [string]$Option
    )

    if ($Seen.ContainsKey($Option)) {
        throw "Use $Option only once."
    }

    $Seen[$Option] = $true
}

# Accepts a distribution name or its number from 'wslm list' and returns
# the real distribution name. Pass -Rows to avoid asking WSL again.
function Resolve-WslmDistro {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [object[]]$Rows
    )

    if (-not $Rows) {
        $Rows = @(Get-WslmDistro)
    }

    # A real name always wins (even if it looks like a number).
    $exact = $Rows | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

    if ($exact) {
        return $exact.Name
    }

    $number = 0

    if ([int]::TryParse($Name, [ref]$number)) {
        $byNumber = $Rows | Where-Object { $_.Number -eq $number } | Select-Object -First 1

        if ($byNumber) {
            return $byNumber.Name
        }

        throw "No distribution is numbered $Name. Run wslm list to see the numbers."
    }

    throw "Distribution '$Name' is not installed, or it is not WSL 2. Run wslm list to see supported distributions."
}

# Distributions available for installation, as rows:
# Family, Name, FriendlyName (parsed from 'wsl --list --online').
function Get-WslmOnlineDistro {
    $output = & $global:WslmWslExePath --list --online 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to retrieve available distributions.'
    }

    # Family names for distro ids whose first word is not a good label.
    $familyAliases = @{
        RLCPlus     = 'Rocky Linux'
        FedoraLinux = 'Fedora'
        kali        = 'Kali Linux'
        archlinux   = 'Arch Linux'
        OracleLinux = 'Oracle Linux'
    }

    $distros = [System.Collections.Generic.List[object]]::new()
    $headerSkipped = $false

    foreach ($entry in $output) {
        # WSL output may contain NUL characters.
        $line = ([string]$entry -replace "`0", '').Trim()

        # Only table rows have two columns separated by 2+ spaces.
        # This skips the intro text and blank lines, in any language.
        if ($line -match '^(\S+)\s{2,}(.+)$') {
            if (-not $headerSkipped) {
                # The first table row is the NAME / FRIENDLY NAME header.
                $headerSkipped = $true
                continue
            }

            $name = $Matches[1]
            $key = ($name -split '[-_]')[0]

            $distros.Add([pscustomobject]@{
                Family       = if ($familyAliases.ContainsKey($key)) { $familyAliases[$key] } else { $key }
                Name         = $name
                FriendlyName = $Matches[2].Trim()
            })
        }
    }

    return $distros.ToArray()
}

# ============================================================
# TABLE RENDERER
# Draws a boxed table. With -GroupColumn, the value is shown
# only on the first row of each group and a separator line is
# drawn between groups. -CellColor can colour individual cells.
# ============================================================

function Write-WslmTable {
    param(
        [Parameter(Mandatory)]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [string[]]$Columns,

        [string[]]$Headers,

        [string]$GroupColumn,

        # Optional: { param($column, $value) 'Green' } returns a colour or $null.
        [scriptblock]$CellColor
    )

    if (-not $Headers) {
        $Headers = $Columns
    }

    # Box characters (by code point, so file encoding never matters).
    $tl = [char]0x250C; $tm = [char]0x252C; $tr = [char]0x2510
    $ml = [char]0x251C; $mm = [char]0x253C; $mr = [char]0x2524
    $bl = [char]0x2514; $bm = [char]0x2534; $br = [char]0x2518
    $h  = [char]0x2500; $v  = [char]0x2502
    $border = 'DarkGray'

    $cell = {
        param($row, $col)
        $value = $row.$col
        if ($null -eq $value) { '' } else { [string]$value }
    }

    # Column widths: widest of header and all cells.
    $widths = @(
        for ($c = 0; $c -lt $Columns.Count; $c++) {
            $max = $Headers[$c].Length

            foreach ($row in $Rows) {
                $len = (& $cell $row $Columns[$c]).Length
                if ($len -gt $max) { $max = $len }
            }

            $max
        }
    )

    $rule = {
        param($left, $mid, $right)
        "$left" + (($widths | ForEach-Object { [string]$h * ($_ + 2) }) -join "$mid") + "$right"
    }

    $writeRow = {
        param($texts, $colors)

        Write-Host "$v" -NoNewline -ForegroundColor $border

        for ($c = 0; $c -lt $texts.Count; $c++) {
            Write-Host (' ' + $texts[$c].PadRight($widths[$c]) + ' ') -NoNewline -ForegroundColor $colors[$c]
            Write-Host "$v" -NoNewline -ForegroundColor $border
        }

        Write-Host
    }

    $groupIdx = if ($GroupColumn) { [array]::IndexOf($Columns, $GroupColumn) } else { -1 }

    Write-Host (& $rule $tl $tm $tr) -ForegroundColor $border
    & $writeRow $Headers (@('Yellow') * $Columns.Count)
    Write-Host (& $rule $ml $mm $mr) -ForegroundColor $border

    $previous = $null
    $first = $true

    foreach ($row in $Rows) {
        $texts = @(foreach ($col in $Columns) { & $cell $row $col })
        $colors = @('White') * $Columns.Count

        if ($CellColor) {
            for ($c = 0; $c -lt $Columns.Count; $c++) {
                $picked = & $CellColor $Columns[$c] $texts[$c]
                if ($picked) { $colors[$c] = $picked }
            }
        }

        if ($groupIdx -ge 0) {
            $key = $texts[$groupIdx]

            if ($key -eq $previous) {
                $texts[$groupIdx] = ''
            }
            else {
                if (-not $first) {
                    Write-Host (& $rule $ml $mm $mr) -ForegroundColor $border
                }
                $previous = $key
            }

            $colors[$groupIdx] = 'Cyan'
        }

        $first = $false
        & $writeRow $texts $colors
    }

    Write-Host (& $rule $bl $bm $br) -ForegroundColor $border
}

# ============================================================
# BACKUP HELPERS
# Backups are plain files in one folder. Nothing else is stored:
# the distro name comes from the file name
#   <Distro>_<yyyy-MM-dd>_<HHmm>.tar   (or .vhdx)
# and the date and size come from the file itself.
# ============================================================

$global:WslmBackupDir = Join-Path $HOME 'WslBackups'

function Get-WslmBackupFolder {
    param([string]$Path)

    if ($Path) {
        return $Path
    }

    return $global:WslmBackupDir
}

function Format-WslmSize {
    param([double]$Bytes)

    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    if ($Bytes -ge 1GB) { return ($Bytes / 1GB).ToString('N1', $inv) + ' GB' }
    if ($Bytes -ge 1MB) { return ($Bytes / 1MB).ToString('N1', $inv) + ' MB' }

    return ([math]::Max(1, [math]::Round($Bytes / 1KB))).ToString('N0', $inv) + ' KB'
}

# Names of all installed distributions, including WSL 1. Used where the
# version does not matter (backup source status, name collisions).
# Empty (never an error) if there are none.
function Get-WslmInstalledName {
    try {
        $output = & $global:WslmWslExePath --list --quiet 2>&1

        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        return @(
            $output |
                ForEach-Object { ([string]$_ -replace "`0", '').Trim() } |
                Where-Object { $_ }
        )
    }
    catch {
        return @()
    }
}

function ConvertTo-WslmBackup {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [string[]]$Installed = @()
    )

    $distro = $null

    if ($File.Name -match '^(.+)_\d{4}-\d{2}-\d{2}_\d{4}\.(tar|vhdx)$') {
        $distro = $Matches[1]
    }

    $source = if (-not $distro) { 'Unknown' }
              elseif ($Installed -contains $distro) { 'Installed' }
              else { 'Removed' }

    [pscustomobject]@{
        Distro     = if ($distro) { $distro } else { '?' }
        Backed     = $File.LastWriteTime
        BackedText = $File.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        Bytes      = $File.Length
        Size       = Format-WslmSize $File.Length
        Source     = $source
        Format     = $File.Extension.TrimStart('.').ToLowerInvariant()
        FileName   = $File.Name
        Path       = $File.FullName
    }
}

# All backups in a folder, grouped by distro (newest first), numbered.
function Get-WslmBackup {
    param(
        [Parameter(Mandatory)]
        [string]$Folder
    )

    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
        return @()
    }

    $installed = @(Get-WslmInstalledName)

    $items = foreach ($file in Get-ChildItem -LiteralPath $Folder -File) {
        if ($file.Extension -in @('.tar', '.vhdx')) {
            ConvertTo-WslmBackup -File $file -Installed $installed
        }
    }

    $n = 0

    return @(
        $items |
            Sort-Object @{ Expression = { $_.Distro } }, @{ Expression = { $_.Backed }; Descending = $true } |
            ForEach-Object {
                $n++
                $_ | Add-Member -NotePropertyName Number -NotePropertyValue $n -PassThru
            }
    )
}

# Accepts a number from 'wslm backup list', a file name in the backup
# folder, or a path to any .tar/.vhdx file. Returns the backup object.
function Resolve-WslmBackup {
    param(
        [Parameter(Mandatory)]
        [string]$Token,

        [object[]]$Backups = @()
    )

    $number = 0

    if ([int]::TryParse($Token, [ref]$number) -and -not (Test-Path -LiteralPath $Token)) {
        $byNumber = $Backups | Where-Object { $_.Number -eq $number } | Select-Object -First 1

        if ($byNumber) {
            return $byNumber
        }

        throw "No backup is numbered $Token. Run wslm backup list to see the numbers."
    }

    $byName = $Backups | Where-Object { $_.FileName -eq $Token } | Select-Object -First 1

    if ($byName) {
        return $byName
    }

    if (Test-Path -LiteralPath $Token -PathType Leaf) {
        $file = Get-Item -LiteralPath $Token

        if ($file.Extension -notin @('.tar', '.vhdx')) {
            throw "'$Token' is not a .tar or .vhdx backup file."
        }

        return ConvertTo-WslmBackup -File $file -Installed @(Get-WslmInstalledName)
    }

    throw "Backup '$Token' was not found. Run wslm backup list to see available backups."
}

# Exports one distribution with 'wsl --export' and returns the new file.
# A running distribution is stopped first (unless -Live) so the files are
# not changing while they are copied.
function Export-WslmBackup {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Folder,

        [switch]$Vhd,
        [switch]$Live
    )

    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    }

    $extension = if ($Vhd) { 'vhdx' } else { 'tar' }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $file = Join-Path $Folder "${Name}_${stamp}.${extension}"

    if (Test-Path -LiteralPath $file) {
        throw "A backup named '$(Split-Path $file -Leaf)' already exists. Try again in a minute."
    }

    $row = Get-WslmDistro | Where-Object Name -eq $Name | Select-Object -First 1

    if ($row -and $row.State -eq 'Running' -and -not $Live) {
        Write-Host "Stopping $Name for a consistent backup ..." -ForegroundColor DarkGray
        Invoke-WslmWslExe -WslArgs @('--terminate', $Name) -Quiet
    }

    $exportArgs = @('--export', $Name, $file)

    if ($Vhd) {
        $exportArgs += '--vhd'
    }

    try {
        Invoke-WslmWslExe -WslArgs $exportArgs -Quiet
    }
    catch {
        # Do not leave a half-written backup behind.
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        }

        throw
    }

    return (Get-Item -LiteralPath $file)
}

# Shows the backup table (used by 'wslm backup list' and 'wslm restore list').
function Show-WslmBackupList {
    param(
        [Parameter(Mandatory)]
        [string]$Folder
    )

    $backups = @(Get-WslmBackup -Folder $Folder)

    if (-not $backups.Count) {
        Write-Host "No backups found in $Folder"
        return
    }

    Write-Host ''

    Write-WslmTable `
        -Rows $backups `
        -Columns @('Number', 'Distro', 'BackedText', 'Size', 'Source') `
        -Headers @('#', 'Distro', 'Backed up', 'Size', 'Source distro') `
        -GroupColumn 'Distro' `
        -CellColor {
            param($column, $value)

            switch ($column) {
                'Number' { 'DarkGray' }
                'Source' {
                    switch ($value) {
                        'Installed' { 'Green' }
                        'Removed'   { 'Yellow' }
                        default     { 'DarkGray' }
                    }
                }
            }
        }

    $total = ($backups | Measure-Object -Property Bytes -Sum).Sum

    Write-Host "`n$($backups.Count) backups, $(Format-WslmSize $total) in $Folder`n" -ForegroundColor DarkGray
}

# ============================================================
# WSLM - command dispatcher
# Single entry point:  wslm <command> [args]
# ============================================================

# Subcommand registry: name -> handler function + description.
$global:WslmCommands = [ordered]@{
    find    = @{ Handler = 'Invoke-WslmFind';    Description = 'Find distributions available for installation' }
    make    = @{ Handler = 'Invoke-WslmMake';    Description = 'Install a distribution' }
    list    = @{ Handler = 'Invoke-WslmList';    Description = 'List installed distributions' }
    shell   = @{ Handler = 'Invoke-WslmShell';   Description = 'Open an interactive shell in a distribution' }
    stop    = @{ Handler = 'Invoke-WslmStop';    Description = 'Stop one or all distributions' }
    default = @{ Handler = 'Invoke-WslmDefault'; Description = 'Show or change the default distribution' }
    backup  = @{ Handler = 'Invoke-WslmBackup';  Description = 'Back up distributions (and list, delete, prune backups)' }
    restore = @{ Handler = 'Invoke-WslmRestore'; Description = 'Restore a distribution from a backup' }
    remove  = @{ Handler = 'Invoke-WslmRemove';  Description = 'Permanently delete a distribution' }
    update  = @{ Handler = 'Invoke-WslmUpdate';  Description = 'Update WSL or show its status' }
}

function Show-WslmHelp {
    Write-Host "`nwslm" -ForegroundColor Cyan
    Write-Host 'A lightweight toolkit for managing WSL distributions.'
    Write-Host "`nUsage: wslm <command> [options]`n"
    Write-Host 'Commands:'

    foreach ($name in $global:WslmCommands.Keys) {
        Write-Host ('  {0,-10}{1}' -f $name, $global:WslmCommands[$name].Description)
    }

    Write-Host "`nRun 'wslm <command> --help' for help on a command.`n"
}

function wslm {
    $tokens = @($args)

    if ($tokens.Count -eq 0 -or $tokens[0] -in @('--help', '-h', 'help')) {
        Show-WslmHelp
        return
    }

    $sub  = ([string]$tokens[0]).ToLowerInvariant()
    $rest = @($tokens | Select-Object -Skip 1)

    if (-not $global:WslmCommands.Contains($sub)) {
        throw "Unknown command '$sub'. Run 'wslm --help' to see available commands."
    }

    $handler = $global:WslmCommands[$sub].Handler

    if (Get-Command $handler -CommandType Function -ErrorAction SilentlyContinue) {
        & $handler @rest
        return
    }

    # Migration fallback: not converted yet, use the old wsl-<name> function.
    $legacy = "wsl-$sub"

    if (Get-Command $legacy -CommandType Function -ErrorAction SilentlyContinue) {
        & $legacy @rest
        return
    }

    throw "Command '$sub' is not available (missing $handler)."
}

# Tab completion for subcommands: wslm <TAB>
Register-ArgumentCompleter -Native -CommandName 'wslm' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # Only complete the first argument (the subcommand).
    $elements = @($commandAst.CommandElements)
    if ($elements.Count -gt 2 -or ($elements.Count -eq 2 -and $wordToComplete -eq '')) { return }

    $global:WslmCommands.Keys |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_, $_, 'ParameterValue', $global:WslmCommands[$_].Description)
        }
}