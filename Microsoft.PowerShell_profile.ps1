$WslToolkit = "$HOME\Documents\PowerShell\WslToolkit"

. "$WslToolkit\helpers.ps1"

Get-ChildItem "$WslToolkit\Commands\*.ps1" |
    ForEach-Object { . $_.FullName }