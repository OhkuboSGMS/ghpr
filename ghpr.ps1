# ghpr - GitHub PR checkout tool (PowerShell)
#
# This file defines the `ghpr` function. It is meant to be dot-sourced from your
# PowerShell profile so that the function runs in your current session and can
# change the current directory after checking out a PR.
#
# Usage:
#   ghpr <pr-number> <owner/repo>
#   ghpr <github-pr-url>
#   ghpr create <owner/repo|repo-url> <branch>
#   ghpr clean [-DryRun] [-Yes] [-Days <N>]
#   ghpr update

# Return $true if the repository has work that could be lost on deletion
# (uncommitted changes or stashed work).
function Test-GhprDirty {
    param([Parameter(Mandatory)][string]$Dir)

    $status = git -C $Dir status --porcelain 2>$null
    if ($status) { return $true }

    $stash = git -C $Dir stash list 2>$null
    if ($stash) { return $true }

    return $false
}

# Return $true if the current HEAD commit exists on some remote-tracking branch
# (i.e. it has been pushed). Protects a `ghpr create` branch whose commits are
# local-only from being deleted.
function Test-GhprBranchPushed {
    param([Parameter(Mandatory)][string]$Dir)

    $remotes = git -C $Dir branch -r --contains HEAD 2>$null
    return [bool]$remotes
}

# Resolve the PR that a `ghpr create` work dir maps to, via its current branch.
# Returns a hashtable with Branch, plus State/Number/Title of the most relevant
# PR (OPEN wins, else MERGED, else CLOSED); State is $null when the branch has
# no PR at all.
function Resolve-GhprCreatePr {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [Parameter(Mandatory)][string]$RepoSlug
    )

    $branch = (git -C $Dir symbolic-ref --quiet --short HEAD 2>$null)
    $result = @{ Branch = $branch; State = $null; Number = $null; Title = $null }
    if (-not $branch) { return $result }

    $json = (gh pr list --repo $RepoSlug --head $branch --state all --json number, state, title 2>$null) | Out-String
    if (-not $json.Trim()) { return $result }

    $prs = @($json | ConvertFrom-Json)
    if ($prs.Count -eq 0) { return $result }

    $pick = $prs | Where-Object { $_.state -eq 'OPEN' } | Select-Object -First 1
    if (-not $pick) { $pick = $prs | Where-Object { $_.state -eq 'MERGED' } | Select-Object -First 1 }
    if (-not $pick) { $pick = $prs | Where-Object { $_.state -eq 'CLOSED' } | Select-Object -First 1 }
    if (-not $pick) { $pick = $prs | Select-Object -First 1 }

    $result.State  = $pick.state
    $result.Number = $pick.number
    $result.Title  = $pick.title
    return $result
}

# Remove work directories under $BaseDir whose PR is merged or closed.
function Invoke-GhprClean {
    param(
        [Parameter(Mandatory)][string]$BaseDir,
        [switch]$DryRun,
        [switch]$Yes,
        [int]$Days = 0
    )

    if (-not (Test-Path $BaseDir)) {
        Write-Host "No work directory found: $BaseDir (nothing to clean)"
        return
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) is required for 'ghpr clean'. Install it from: https://cli.github.com/"
        return
    }

    Write-Host "==> Scanning $BaseDir for cleanup candidates..."

    $toDelete = @()
    $skipped  = @()
    $kept     = @()
    $unknown  = @()

    $cutoff = if ($Days -gt 0) { (Get-Date).AddDays(-$Days) } else { $null }

    Get-ChildItem -Path $BaseDir -Directory |
        ForEach-Object {
            $dir = $_.FullName
            $name = $_.Name
            $lastWrite = $_.LastWriteTime

            if (-not (Test-Path (Join-Path $dir '.git'))) {
                $unknown += [pscustomobject]@{ Name = $name; Reason = 'not a git repository' }
                return
            }

            $remoteUrl = (git -C $dir remote get-url origin 2>$null)
            $repoSlug = $null
            if ($remoteUrl -match 'github\.com[:/]+([^/]+)/([^/]+)') {
                $repoSlug = "$($Matches[1])/$(($Matches[2] -replace '\.git$', ''))"
            }
            if (-not $repoSlug) {
                $unknown += [pscustomobject]@{ Name = $name; Reason = 'no GitHub remote found' }
                return
            }

            # PR checkout dirs are "<repo>-pr<number>" (look up by number); every
            # other dir is treated as a `ghpr create` dir (look up by branch).
            $state = $null; $title = $null; $prLabel = $null; $isCreate = $false
            if ($name -match '-pr(\d+)$') {
                $prNumber = $Matches[1]
                $prLabel = "#$prNumber"
                $json = (gh pr view $prNumber --repo $repoSlug --json state, title 2>$null) | Out-String
                if (-not $json.Trim()) {
                    $unknown += [pscustomobject]@{ Name = $name; Reason = "could not fetch PR $repoSlug#$prNumber" }
                    return
                }
                $pr = $json | ConvertFrom-Json
                $state = $pr.state
                $title = $pr.title
            }
            else {
                $isCreate = $true
                $resolved = Resolve-GhprCreatePr -Dir $dir -RepoSlug $repoSlug
                if (-not $resolved.Branch) {
                    $unknown += [pscustomobject]@{ Name = $name; Reason = 'detached HEAD (no branch)' }
                    return
                }
                if (-not $resolved.State) {
                    $unknown += [pscustomobject]@{ Name = $name; Reason = "no PR for branch '$($resolved.Branch)' (local-only)" }
                    return
                }
                $state = $resolved.State
                $title = $resolved.Title
                $prLabel = "#$($resolved.Number) (branch $($resolved.Branch))"
            }

            $stale = $false
            if ($cutoff -and $lastWrite -lt $cutoff) { $stale = $true }

            if ($state -eq 'MERGED' -or $state -eq 'CLOSED' -or $stale) {
                $reason = $null
                if (Test-GhprDirty -Dir $dir) {
                    $reason = 'uncommitted changes or stashes'
                }
                elseif ($isCreate -and $state -eq 'CLOSED' -and -not (Test-GhprBranchPushed -Dir $dir)) {
                    $reason = 'closed PR, local commits not pushed'
                }
                if ($reason) {
                    $skipped += [pscustomobject]@{ Name = $name; Info = "$state $repoSlug $prLabel ($reason)" }
                }
                else {
                    $toDelete += [pscustomobject]@{ Dir = $dir; Name = $name; Slug = $repoSlug; PrLabel = $prLabel; State = $state; Title = $title }
                }
            }
            else {
                $kept += [pscustomobject]@{ Name = $name; Info = "$state $repoSlug $prLabel" }
            }
        }

    # ----- Report -----
    $deleteLabel = if ($Days -gt 0) { "PR merged/closed or not modified for $Days+ days" } else { 'PR merged/closed' }

    Write-Host ""
    if ($toDelete.Count -gt 0) {
        Write-Host "To delete ($deleteLabel):"
        foreach ($c in $toDelete) {
            Write-Host ("  [{0}] {1,-40} {2} {3}  {4}" -f $c.State, $c.Name, $c.Slug, $c.PrLabel, $c.Title)
        }
        Write-Host ""
    }
    if ($skipped.Count -gt 0) {
        Write-Host "Skipped (local work would be lost):"
        foreach ($s in $skipped) { Write-Host "  $($s.Name)  $($s.Info)" }
        Write-Host ""
    }
    if ($unknown.Count -gt 0) {
        Write-Host "Unknown (PR state undetermined, kept):"
        foreach ($u in $unknown) { Write-Host "  $($u.Name)  $($u.Reason)" }
        Write-Host ""
    }
    if ($kept.Count -gt 0) {
        Write-Host "Kept (PR still open):"
        foreach ($k in $kept) { Write-Host "  $($k.Name)  $($k.Info)" }
        Write-Host ""
    }

    if ($toDelete.Count -eq 0) {
        Write-Host "Nothing to delete."
        return
    }

    $totalBytes = 0
    foreach ($c in $toDelete) {
        $sum = (Get-ChildItem -LiteralPath $c.Dir -Recurse -Force -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        if ($sum) { $totalBytes += $sum }
    }
    $totalMb = [math]::Round($totalBytes / 1MB, 1)
    Write-Host "$($toDelete.Count) directory(ies) to delete (~${totalMb} MB)."

    if ($DryRun) {
        Write-Host "(dry-run) No directories were removed."
        return
    }

    if (-not $Yes) {
        $answer = Read-Host "Proceed with deletion? [y/N]"
        if ($answer -notmatch '^(y|yes)$') {
            Write-Host "Aborted. No directories were removed."
            return
        }
    }

    $removed = 0
    foreach ($c in $toDelete) {
        Write-Host "  removing $($c.Dir)"
        Remove-Item -Recurse -Force -LiteralPath $c.Dir
        $removed++
    }
    Write-Host "==> Removed $removed directory(ies)."
}

# Clone <repo> and create <branch> off the latest default branch.
# Mirrors the layout of PR checkout dirs: ~/work/prs/<repo>-<branch>/
function Invoke-GhprCreate {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$Branch
    )

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) is required for 'ghpr create'. Install it from: https://cli.github.com/"
        return
    }

    # Normalize repo argument to an "owner/repo" slug
    $repoSlug = $null
    if ($Repo -match 'github\.com[:/]+([^/]+)/([^/]+)') {
        $repoSlug = "$($Matches[1])/$($Matches[2] -replace '\.git$', '')"
    }
    else {
        $repoSlug = $Repo -replace '\.git$', ''
    }

    $repoName  = $repoSlug.Split('/')[-1]
    $branchDir = $Branch -replace '/', '-'   # flatten slashes for the dir name
    $baseDir   = Join-Path $HOME "work\prs"
    $workDir   = Join-Path $baseDir "$repoName-$branchDir"

    if (-not (Test-Path $baseDir)) {
        New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
    }

    Write-Host "==> Use workdir: $workDir"

    if (-not (Test-Path (Join-Path $workDir ".git"))) {
        Write-Host "==> No git repo found in $workDir. Cloning via gh repo clone..."
        if (Test-Path $workDir) {
            Remove-Item -Recurse -Force $workDir
        }
        gh repo clone $repoSlug $workDir
        if ($LASTEXITCODE -ne 0) {
            Write-Error "gh repo clone failed"
            return
        }
    }
    else {
        Write-Host "==> Existing git repo found in $workDir"
    }

    Set-Location $workDir

    # Resolve default branch from GitHub, fall back to local HEAD, then 'main'
    $defaultBranch = (gh repo view $repoSlug --json defaultBranchRef --jq '.defaultBranchRef.name' 2>$null)
    if (-not $defaultBranch) {
        $defaultBranch = (git symbolic-ref --short refs/remotes/origin/HEAD 2>$null) -replace '^origin/', ''
    }
    if (-not $defaultBranch) { $defaultBranch = 'main' }

    Write-Host "==> Fetching latest origin/$defaultBranch..."
    git fetch origin $defaultBranch

    git show-ref --verify --quiet "refs/heads/$Branch" 2>$null
    $localExists = ($LASTEXITCODE -eq 0)

    if ($localExists) {
        Write-Host "==> Branch '$Branch' already exists locally; checking it out"
        git checkout $Branch
    }
    else {
        git show-ref --verify --quiet "refs/remotes/origin/$Branch" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Note: a remote branch 'origin/$Branch' already exists." -ForegroundColor Yellow
            Write-Host "      Creating a fresh local branch from origin/$defaultBranch as requested." -ForegroundColor Yellow
        }
        Write-Host "==> Creating branch '$Branch' from origin/$defaultBranch"
        # --no-track: leave upstream unset until the user pushes the branch
        git checkout -b $Branch --no-track "origin/$defaultBranch"
    }
}

# Download the latest ghpr.ps1 from GitHub and replace the installed copy.
function Invoke-GhprUpdate {
    $ghprRepo   = if ($env:GHPR_REPO)   { $env:GHPR_REPO }   else { 'OhkuboSGMS/ghpr' }
    $ghprBranch = if ($env:GHPR_BRANCH) { $env:GHPR_BRANCH } else { 'master' }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) is required for 'ghpr update'. Install it from: https://cli.github.com/"
        return
    }

    $binDir = Join-Path $HOME ".local\bin"
    $target = Join-Path $binDir "ghpr.ps1"

    if (-not (Test-Path $target)) {
        Write-Error "Installed ghpr.ps1 not found at $target. Run install.ps1 first."
        return
    }

    Write-Host "==> Updating ghpr from ${ghprRepo}@${ghprBranch}..."

    $tmpFile = Join-Path $binDir ".ghpr-update-tmp.ps1"
    try {
        $b64 = gh api "repos/${ghprRepo}/contents/ghpr.ps1?ref=${ghprBranch}" --jq '.content' 2>$null
        if (-not $b64) {
            Write-Error "Failed to download ghpr.ps1 from ${ghprRepo}@${ghprBranch}"
            return
        }
        $bytes = [Convert]::FromBase64String($b64)
        [IO.File]::WriteAllBytes($tmpFile, $bytes)

        if ((Get-Item $tmpFile).Length -eq 0) {
            Write-Error "Downloaded ghpr.ps1 is empty; aborting (nothing was changed)"
            Remove-Item $tmpFile -Force
            return
        }

        Move-Item -Path $tmpFile -Destination $target -Force
        Write-Host "==> Updated $target" -ForegroundColor Green
        Write-Host "    Reload the function to pick up changes: . `$PROFILE  (or open a new shell)"
    }
    catch {
        Write-Error "Update failed: $_"
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
    }
}

function ghpr {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$First,

        [Parameter(Position = 1)]
        [string]$Second,

        [Parameter(Position = 2)]
        [string]$Third,

        [switch]$DryRun,
        [switch]$Yes,
        [int]$Days = 0
    )

    $usage = @"
Usage:
  ghpr <pr-number> <owner/repo>
  ghpr <github-pr-url>
  ghpr create <owner/repo|repo-url> <branch>
  ghpr clean [-DryRun] [-Yes] [-Days <N>]
  ghpr update

Examples:
  ghpr 125 octocat/Hello-World
  ghpr https://github.com/octocat/Hello-World/pull/125
  ghpr create octocat/Hello-World feature/login
  ghpr clean            # remove work dirs whose PR is merged/closed
  ghpr clean -DryRun    # list candidates without deleting
  ghpr update           # update ghpr itself to the latest version
"@

    $baseDir = Join-Path $HOME "work\prs"

    # Subcommand: update / self-update / upgrade
    if ($First -eq 'update' -or $First -eq 'self-update' -or $First -eq 'upgrade') {
        Invoke-GhprUpdate
        return
    }

    # Subcommand: create
    if ($First -eq 'create') {
        if (-not $Second -or -not $Third) {
            Write-Host "Usage: ghpr create <owner/repo|repo-url> <branch>"
            return
        }
        Invoke-GhprCreate -Repo $Second -Branch $Third
        return
    }

    # Subcommand: clean / prune (does not change the current directory)
    if ($First -eq 'clean' -or $First -eq 'prune') {
        Invoke-GhprClean -BaseDir $baseDir -DryRun:$DryRun -Yes:$Yes -Days $Days
        return
    }

    $repo = $null
    $prNumber = $null

    if ($First -and -not $Second) {
        # Single argument - assume it's a GitHub PR URL
        if ($First -match '^https?://github\.com/([^/]+/[^/]+)/pull/([0-9]+)') {
            $repo = $Matches[1]
            $prNumber = $Matches[2]
        }
        else {
            Write-Error "Invalid GitHub PR URL format`nExpected: https://github.com/owner/repo/pull/<number>`n`n$usage"
            return
        }
    }
    elseif ($First -and $Second) {
        # Two arguments - original format
        $prNumber = $First
        $repo = $Second
    }
    else {
        Write-Host $usage
        return
    }

    # Check dependencies
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI (gh) is not installed. Install it from: https://cli.github.com/"
        return
    }

    if (-not (Test-Path $baseDir)) {
        New-Item -ItemType Directory -Force -Path $baseDir | Out-Null
    }

    $repoName = $repo.Split('/')[-1]
    $workDir = Join-Path $baseDir "$repoName-pr$prNumber"

    Write-Host "==> Use workdir: $workDir"

    if (-not (Test-Path (Join-Path $workDir ".git"))) {
        Write-Host "==> No git repo found in $workDir. Cloning via gh repo clone..."
        if (Test-Path $workDir) {
            Remove-Item -Recurse -Force $workDir
        }
        gh repo clone $repo $workDir
        if ($LASTEXITCODE -ne 0) {
            Write-Error "gh repo clone failed"
            return
        }
    }
    else {
        Write-Host "==> Existing git repo found in $workDir"
    }

    Set-Location $workDir

    Write-Host "==> Running: gh pr checkout $prNumber --repo $repo"
    gh pr checkout $prNumber --repo $repo
    if ($LASTEXITCODE -ne 0) {
        Write-Error "gh pr checkout failed"
        return
    }
}
