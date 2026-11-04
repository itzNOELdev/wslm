function Invoke-WslmShell {
    $tokens = @($args)

    if ($tokens -contains '--help') {
        Show-WslmCommandHelp `
            -Command 'wslm shell' `
            -Usage 'wslm shell <Distro|#> [--user <User>] [--help]' `
            -Description 'Open an interactive shell in a WSL 2 distribution (by name or number from wslm list).'
        return
    }

    $user = $null
    $seen = @{}
    $names = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = [string]$tokens[$i]

        if ($token -in @('--background', '--all')) {
            throw 'wslm shell is interactive only. Start background distributions with wsl directly.'
        }
        elseif ($token -eq '--user') {
            Assert-WslmOptionOnce -Seen $seen -Option $token

            if (($i + 1) -ge $tokens.Count -or ([string]$tokens[$i + 1]).StartsWith('--')) {
                throw 'Provide a username after --user.'
            }

            $user = [string]$tokens[++$i]
        }
        elseif ($token.StartsWith('--')) {
            throw "Unknown option: $token"
        }
        else {
            $names.Add($token)
        }
    }

    if ($names.Count -ne 1) {
        throw 'Usage: wslm shell <Distro|#> [--user <User>] [--help]'
    }

    $name = Resolve-WslmDistro -Name $names[0]
    $shellArgs = @('--distribution', $name)

    if ($user) {
        $shellArgs += @('--user', $user)
    }

    # The shell's own exit code (the last command you ran) is not an error.
    & $global:WslmWslExePath @shellArgs
}
