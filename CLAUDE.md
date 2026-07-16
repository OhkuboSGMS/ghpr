# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`ghpr` is a shell script-based command-line tool for checking out GitHub Pull Requests. It provides a streamlined workflow for PR review by automatically cloning repositories and switching to dedicated work directories.

## Architecture

The tool consists of two main components that work together:

1. **Core Script (`ghpr`)**: A standalone Bash script that handles the PR checkout logic. It cannot change the parent shell's directory due to Unix process isolation.

2. **Shell Function Wrapper (`ghpr.sh`)**: A shell function sourced into the user's shell that wraps the core script and changes directory after execution. This is the key architectural pattern that allows automatic `cd` functionality.

This two-part architecture is necessary because:
- The core script runs in a subprocess and cannot affect the parent shell's working directory
- The shell function runs in the current shell and can use `cd` to change directories
- The function calculates the work directory using the same logic as the core script, ensuring they stay synchronized

3. **Windows PowerShell (`ghpr.ps1`)**: A self-contained PowerShell `ghpr` function that mirrors the Bash logic. Because a PowerShell function dot-sourced into the session can call `Set-Location` directly, no separate subprocess/wrapper split is needed — all logic (argument parsing, clone, `gh pr checkout`, and `cd`) lives in this one function. It is installed via `install.ps1` (copies to `~\.local\bin\ghpr.ps1` and dot-sources it from `$PROFILE`) and removed via `uninstall.ps1`.

## Subcommands

In addition to PR checkout, `ghpr` dispatches on a leading subcommand keyword:

- **`ghpr create <owner/repo> <branch>`**: Clones the repository (if not already present) and creates a new branch off the latest default branch (main/master). Work directory naming: `~/work/prs/<repo-name>-<branch-dir>/` where slashes in the branch name are replaced with dashes. After creation, automatically `cd`s into the work directory. If the branch already exists locally it checks it out; if a remote branch of the same name exists a warning is shown but a fresh local branch is still created from the default branch (`--no-track`). Accepts full GitHub URLs or bare `owner/repo` slugs.
- **`ghpr clean`** (alias `prune`): Removes work directories under `~/work/prs/` whose PR is merged or closed. For each `*-pr<number>` directory it derives `owner/repo` from the clone's `origin` remote and queries `gh pr view <number> --repo <slug> --json state`. MERGED/CLOSED → deletion candidate; OPEN → kept; undeterminable (not a git repo / no GitHub remote / `gh` failure) → "unknown", kept. Directories with uncommitted changes or stashes are always skipped so local work is never lost. Deletion is interactive (lists candidates + total size, confirms) unless `-y/--yes`. Options: `-n/--dry-run`, `-y/--yes`, `--days <N>` (also flag dirs not modified for N+ days). The dirty check intentionally does NOT flag unpushed commits, because PR-review clones normally contain commits from the PR head that aren't on `origin`.
- **`ghpr update`** (aliases `self-update`, `upgrade`): Downloads the latest `ghpr` and `ghpr.sh` (Bash) or `ghpr.ps1` (PowerShell) from `OhkuboSGMS/ghpr@master` via `gh api` and replaces the installed copies in `~/.local/bin`. Aborts if the downloaded file is empty. Override source with env vars `GHPR_REPO` and `GHPR_BRANCH`.
- Subcommand dispatch happens in BOTH the core `ghpr` script and the `ghpr.sh` wrapper. The wrapper must intercept `clean`/`prune`/`update` and pass them straight through (no `cd` afterward). For `create`, the wrapper passes through to the core script then `cd`s into the resulting work directory. The PowerShell `ghpr` function branches to `Invoke-GhprClean`, `Invoke-GhprCreate`, or `Invoke-GhprUpdate`. PowerShell options for clean: `-DryRun`, `-Yes`, `-Days`.

## Directory Structure

Work directories are organized under `~/work/prs/` with the pattern:
```
~/work/prs/<repo-name>-pr<number>/
```

Examples:
- `~/work/prs/Hello-World-pr125/`
- `~/work/prs/Spoon-Knife-pr13/`

## Installation Mechanism

The `install.sh` script:
1. Copies `ghpr` to `~/.local/bin/ghpr` (the core script)
2. Copies `ghpr.sh` to `~/.local/bin/ghpr.sh` (the shell function)
3. Adds a source line to `~/.bashrc` or `~/.zshrc` to load the shell function
4. Does NOT modify PATH if `~/.local/bin` is already included

## Testing

To test changes manually:
```bash
# Test the core script directly
bash ghpr 125 owner/repo

# Test with a PR URL
bash ghpr https://github.com/owner/repo/pull/125

# Test the cleanup subcommand without deleting anything
bash ghpr clean --dry-run

# After installing, test the full workflow (including auto-cd)
source ~/.zshrc  # or ~/.bashrc
ghpr 125 owner/repo
pwd  # Should be in ~/work/prs/repo-pr125/
```

## Dependencies

- **GitHub CLI (`gh`)**: Required for all GitHub API operations
  - Used for `gh repo clone` to clone repositories
  - Used for `gh pr checkout` to check out PR branches
- **git**: Required for repository operations

## Development Notes

- Both `ghpr` and `ghpr.sh` must parse arguments identically to ensure work directory paths match (including subcommand dispatch for `clean`/`prune`)
- The regex pattern for PR URL parsing is: `^https?://github\.com/([^/]+/[^/]+)/pull/([0-9]+)`
- `clean` parses `owner/repo` back out of a remote URL with `github\.com[:/]+([^/]+)/([^/]+)` (handles both https and ssh forms; strips a trailing `.git`)
- Both scripts handle bash and zsh differences (e.g., `BASH_REMATCH` vs `match` array)
- Error handling uses `set -euo pipefail` in the core script for safety
- The shell function uses `return` instead of `exit` to avoid closing the user's shell
