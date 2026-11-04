# WSL Toolkit

A lightweight PowerShell 7 toolkit for managing WSL distributions on Windows.
Everything lives behind one command, `wslm`, with subcommands, like `git` or `docker`.

```powershell
wslm <command> [options]
wslm --help
wslm <command> --help
```

## Commands

| Command | Purpose |
|---|---|
| `wslm find` | Find distributions available for installation |
| `wslm make` | Install a distribution |
| `wslm list` | List installed distributions |
| `wslm start` | Open a shell in a distribution, or start it in the background |
| `wslm stop` | Stop distributions |
| `wslm default` | Show or change the default distribution |
| `wslm backup` | Back up distributions; list, delete and prune backups |
| `wslm restore` | Restore a distribution from a backup |
| `wslm remove` | Permanently delete distributions |
| `wslm update` | Update WSL, or show its status |

## Install

1. Copy this folder to `Documents\PowerShell\WslToolkit`.
2. Add these lines to your PowerShell profile (run `notepad $PROFILE` to open it):

```powershell
$WslToolkit = "$HOME\Documents\PowerShell\WslToolkit"

. "$WslToolkit\helpers.ps1"

Get-ChildItem "$WslToolkit\Commands\*.ps1" |
    ForEach-Object { . $_.FullName }
```

3. Restart PowerShell.

### Folder layout

```
WslToolkit/
├── helpers.ps1            shared helpers, table renderer, the wslm dispatcher
└── Commands/
    ├── wslm-find.ps1
    ├── wslm-make.ps1
    ├── wslm-list.ps1
    ├── wslm-start.ps1
    ├── wslm-stop.ps1
    ├── wslm-default.ps1
    ├── wslm-backup.ps1
    ├── wslm-restore.ps1
    ├── wslm-remove.ps1
    └── wslm-update.ps1
```

Each file in `Commands` defines one function, `Invoke-Wslm<Name>`, which `wslm` calls.

## Names or numbers

`wslm list` numbers every distribution. Anywhere a distribution name is accepted, its number works too:

```powershell
wslm list
wslm stop 2
wslm default 1
```

Numbers are assigned alphabetically by name, so they do not change when you change the default or a distribution starts or stops. Filters such as `--running` keep the numbers from the full list. If a distribution is actually named `2`, the name wins.

Commands that take several targets check all of them before doing anything, so a typo never leaves a half-finished operation.

## Usage

### Find

```powershell
wslm find
wslm find --name ubuntu
```

Shows the distributions you can install, grouped by family in a table. `--name` matches the name, the friendly name or the family, ignoring case.

### Make

```powershell
wslm make Ubuntu-24.04
wslm make Debian --no-launch
```

Installs a distribution. The name is checked against the online list first (with suggestions if it does not match), and an already-installed distribution is reported instead of failing. `--no-launch` installs without starting it.

### List

```powershell
wslm list
wslm list --running
wslm list --stopped
wslm list --verbose
```

```
┌───┬──────────────┬─────────┬─────────┐
│ # │ Name         │ State   │ Default │
├───┼──────────────┼─────────┼─────────┤
│ 1 │ Debian       │ Stopped │         │
│ 2 │ Ubuntu-24.04 │ Running │ *       │
└───┴──────────────┴─────────┴─────────┘
```

`--verbose` adds the WSL version (1 or 2) column.

### Start

```powershell
wslm start 2                       # open a shell
wslm start Debian --user root      # open a shell as a specific user
wslm start 1 2 --background        # start without a shell and keep running
wslm start --all                   # start everything in the background
```

Without `--background`, `start` opens an interactive shell. With `--background` (and with `--all`), the distribution is started without a shell and kept running by a hidden process inside it, because WSL stops a distribution shortly after its last process ends. Use `wslm stop` to end it.

### Stop

```powershell
wslm stop 2
wslm stop Debian Ubuntu-24.04
wslm stop --all
```

Stops one or more distributions. Distributions that are already stopped are skipped. `--all` shuts down WSL completely.

### Default

```powershell
wslm default          # show the current default
wslm default 1        # set the default
```

### Backup

```powershell
wslm backup 2                      # back up one distribution
wslm backup 1 2                    # several at once
wslm backup --all
wslm backup 2 --vhd                # save as a .vhdx disk image (WSL 2 only)
wslm backup 2 --live               # do not stop the distribution first
wslm backup 2 --out D:\Backups     # use another folder

wslm backup list
wslm backup delete 3 [--force]
wslm backup prune --keep 3 [--force]
```

Backups are made with `wsl --export` and saved as plain files in `$HOME\WslBackups` (change per command with `--out`). A running distribution is stopped first so its files are not changing during the export, unless you pass `--live`.

File names follow `<Distro>_<yyyy-MM-dd>_<HHmm>.tar` (or `.vhdx`). Nothing else is stored: the distribution name comes from the file name, and the date and size come from the file.

`wslm backup list` also shows whether each backup's source distribution is still installed or has since been removed:

```
┌───┬──────────────┬──────────────────┬────────┬───────────────┐
│ # │ Distro       │ Backed up        │ Size   │ Source distro │
├───┼──────────────┼──────────────────┼────────┼───────────────┤
│ 1 │ Debian       │ 2026-11-04 14:20 │ 1.1 GB │ Installed     │
├───┼──────────────┼──────────────────┼────────┼───────────────┤
│ 2 │ Ubuntu-24.04 │ 2026-11-04 09:05 │ 3.4 GB │ Removed       │
│   │ Ubuntu-24.04 │ 2026-10-28 22:10 │ 3.1 GB │ Removed       │
└───┴──────────────┴──────────────────┴────────┴───────────────┘
```

`delete` and `prune` list what they will remove and ask you to type `YES`. `prune --keep N` keeps the newest N backups per distribution.

### Restore

```powershell
wslm restore 3                      # back under its original name
wslm restore 3 --name Ubuntu-test   # restore as a copy
wslm restore 3 --replace            # overwrite the existing distribution
wslm restore 3 --path D:\WSL\Ubuntu # choose the install folder
wslm restore list                   # same table as wslm backup list
```

Restores with `wsl --import`. The default install folder is `$HOME\WSL\<Name>`. A backup can also be given as a file name or a path to any `.tar` / `.vhdx` file.

| Situation | What happens |
|---|---|
| The distribution was removed | Restores under its original name. |
| The distribution still exists | Refuses, and suggests `--name <New>` (a copy) or `--replace`. |
| `--replace` | Asks for `YES`, offers a safety backup of the current distribution, deletes it, then restores. |

`wsl --import` logs in as `root`. After restoring, the toolkit looks for the regular user (UID 1000) inside the distribution and records it as the default user in `/etc/wsl.conf`. This is best effort and only warns if it fails. Use `--user <name>` to choose the user, or `--no-user-fix` to skip it.

### Remove

```powershell
wslm remove 2
wslm remove 1 3
wslm remove Debian --force
wslm remove --all
```

Permanently deletes distributions. One distribution asks for `YES`; several list their names first and ask for `YES`; `--all` asks for `REMOVE ALL`. `--force` skips the question. If one removal fails the rest still run, and the failures are reported at the end. **This cannot be undone. Use `wslm backup` first.**

### Update

```powershell
wslm update                  # update WSL
wslm update --web-download   # download the update from the web instead of the Store
wslm update --status         # version and status in one table
```

After an update it reports the old and new WSL version (`WSL updated: 2.4.9 -> 2.5.1`) or that WSL is already up to date.

## Requirements

- Windows with WSL installed
- PowerShell 7
- Run PowerShell as Administrator only if a WSL operation asks for it