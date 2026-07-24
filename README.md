# ghpr - GitHub PR Checkout Tool

A simple command-line tool to quickly checkout GitHub Pull Requests and automatically switch to the work directory.

## Features

- ✅ Checkout GitHub PRs with a single command
- ✅ Supports both PR number + repo format and full GitHub URL
- ✅ Automatically clones the repository if not already cloned
- ✅ Automatically switches to the PR work directory
- ✅ Cleans up work directories whose PR is already merged/closed (`ghpr clean`)
- ✅ Works with bash, zsh, and Windows PowerShell
- ✅ Organized workspace in `~/work/prs/`

## Prerequisites

- [GitHub CLI (gh)](https://cli.github.com/) - Required for GitHub API access
- git - Required for repository operations
- bash or zsh shell (macOS/Linux), or PowerShell 5.1+ (Windows)

## Installation

### Windows (PowerShell)

1. Clone or download this repository, then run the PowerShell installer:
   ```powershell
   .\install.ps1
   ```

   This copies `ghpr.ps1` to `~\.local\bin\` and adds a line to your PowerShell
   profile (`$PROFILE`) that loads the `ghpr` function in every session.

2. Reload your profile (or open a new terminal):
   ```powershell
   . $PROFILE
   ```

   If scripts are blocked, allow them once for your user:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```

To uninstall on Windows:
```powershell
.\uninstall.ps1
```

### Quick Install (no clone required)

You can install directly using `gh api` without cloning the repository:

```bash
mkdir -p ~/.local/bin
gh api repos/OhkuboSGMS/ghpr/contents/ghpr --jq '.content' | base64 -d > ~/.local/bin/ghpr
gh api repos/OhkuboSGMS/ghpr/contents/ghpr.sh --jq '.content' | base64 -d > ~/.local/bin/ghpr.sh
chmod +x ~/.local/bin/ghpr

# Add to your shell config (zsh)
echo 'source "$HOME/.local/bin/ghpr.sh"' >> ~/.zshrc
source ~/.zshrc

# For bash
# echo 'source "$HOME/.local/bin/ghpr.sh"' >> ~/.bashrc
# source ~/.bashrc
```

### macOS / Linux (install from source)

1. Clone or download this repository:
   ```bash
   cd ~/repository
   git clone <this-repo-url> ghpr-tool
   cd ghpr-tool
   ```

2. Run the install script:
   ```bash
   bash install.sh
   ```

3. Reload your shell configuration:
   ```bash
   # For zsh
   source ~/.zshrc

   # For bash
   source ~/.bashrc
   ```

## Usage

### Format 1: PR number + repository

```bash
ghpr <pr-number> <owner/repo>
```

Example:
```bash
ghpr 125 octocat/Hello-World
```

### Format 2: GitHub PR URL

```bash
ghpr <github-pr-url>
```

Example:
```bash
ghpr https://github.com/octocat/Hello-World/pull/125
```

### Cleaning up old work directories

Over time `~/work/prs/` fills up with clones for PRs you've already finished
reviewing. `ghpr clean` finds the ones that are no longer in use and removes
them:

```bash
ghpr clean              # list candidates, then ask before deleting
ghpr clean --dry-run    # only list candidates, never delete
ghpr clean --yes        # delete without the confirmation prompt
ghpr clean --days 30    # also flag dirs not modified for 30+ days
```

A work directory is considered **unused** when its PR is **merged or closed**
(determined via `gh`, using each clone's `origin` remote). This covers both
kinds of work dir:

- **PR checkout dirs** (`<repo>-pr<number>`) — matched by the PR number in the
  folder name.
- **`ghpr create` dirs** (`<repo>-<branch>`) — matched by looking up the PR
  whose head is the dir's current branch. A `create` branch that has **no PR
  yet** (e.g. never pushed) is kept, so you never lose local-only work.

For safety:

- Directories with **uncommitted changes or stashes are always kept**, even if
  the PR is merged/closed — so you never lose local work.
- A `create` dir whose PR is **closed (not merged)** is kept when its commits
  were never pushed anywhere — the local clone may be the only copy.
- Directories whose PR is still **open** are kept.
- Directories whose state can't be determined (not a git repo, no GitHub
  remote, detached HEAD, a branch with no PR, or `gh` can't reach the PR) are
  kept and listed under *Unknown*.

Deletion is interactive by default: candidates are listed with their total
size, and nothing is removed until you confirm. `prune` is accepted as an alias
for `clean`.

On Windows (PowerShell), use switch-style options instead:

```powershell
ghpr clean -DryRun
ghpr clean -Yes
ghpr clean -Days 30
```

## How It Works

1. **First Run**:
   - Creates workspace directory: `~/work/prs/`
   - Clones the repository to: `~/work/prs/<repo-name>-pr<number>/`
   - Checks out the PR branch
   - Automatically `cd` to the work directory

2. **Subsequent Runs**:
   - Reuses existing repository
   - Checks out the PR branch (updates if needed)
   - Automatically `cd` to the work directory

## Directory Structure

```
~/work/prs/
├── Hello-World-pr125/
│   └── .git/
│   └── ... (repository files)
├── Spoon-Knife-pr13/
│   └── .git/
│   └── ... (repository files)
└── ...
```

## Examples

### Scenario 1: Check out a PR from a link

You see a PR link in Slack or GitHub:
```
https://github.com/octocat/Spoon-Knife/pull/13
```

Just paste it:
```bash
ghpr https://github.com/octocat/Spoon-Knife/pull/13
```

Output:
```
==> Use workdir: /Users/username/work/prs/Spoon-Knife-pr13
==> Cloning via gh repo clone...
==> Running: gh pr checkout 13 --repo octocat/Spoon-Knife
Switched to a new branch 'feature/update-readme'
```

You're now in the PR directory, ready to review code!

### Scenario 2: Check out using PR number

```bash
ghpr 125 octocat/Hello-World
```

Output:
```
==> Use workdir: /Users/username/work/prs/Hello-World-pr125
==> Existing git repo found in /Users/username/work/prs/Hello-World-pr125
==> Running: gh pr checkout 125 --repo octocat/Hello-World
Already on 'feature/update-logic'
```

## Uninstallation

On macOS / Linux, run the uninstall script:
```bash
bash uninstall.sh
```

On Windows, run the PowerShell uninstaller:
```powershell
.\uninstall.ps1
```

This will:
- Remove `~/.local/bin/ghpr` and `~/.local/bin/ghpr.sh`
- Remove the shell function from your config files
- Create backups of modified config files

Note: Work directories in `~/work/prs/` are not automatically removed. Use
`ghpr clean` to remove the ones whose PR is merged/closed, or delete everything
manually if needed:
```bash
ghpr clean        # remove finished PR work dirs (safe: keeps dirty/open ones)
rm -rf ~/work/prs/  # or wipe the whole workspace
```

## Troubleshooting

### "gh: command not found"

Install GitHub CLI:
```bash
# macOS
brew install gh

# Linux
# See: https://github.com/cli/cli#installation
```

### "~/.local/bin is not in your PATH"

Add this to your shell config file (`~/.zshrc` or `~/.bashrc`):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload your shell.

### Shell function not working

Make sure you've reloaded your shell configuration:
```bash
source ~/.zshrc  # or ~/.bashrc
```

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
