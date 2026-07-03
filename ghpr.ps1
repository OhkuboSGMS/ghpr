# ghpr - GitHub PR checkout tool (PowerShell)
#
# This file defines the `ghpr` function. It is meant to be dot-sourced from your
# PowerShell profile so that the function runs in your current session and can
# change the current directory after checking out a PR.
#
# Usage:
#   ghpr <pr-number> <owner/repo>
#   ghpr <github-pr-url>
#   ghpr clean [-DryRun] [-Yes] [-Days <N>]

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
        Where-Object { $_.Name -match '-pr(\d+)$' } |
        ForEach-Object {
            $dir = $_.FullName
            $name = $_.Name
            $null = $name -match '-pr(\d+)$'
            $prNumber = $Matches[1]

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

            $json = (gh pr view $prNumber --repo $repoSlug --json state, title 2>$null) | Out-String
            if (-not $json.Trim()) {
                $unknown += [pscustomobject]@{ Name = $name; Reason = "could not fetch PR $repoSlug#$prNumber" }
                return
            }
            $pr = $json | ConvertFrom-Json
            $state = $pr.state
            $title = $pr.title

            $stale = $false
            if ($cutoff -and $_.LastWriteTime -lt $cutoff) { $stale = $true }

            if ($state -eq 'MERGED' -or $state -eq 'CLOSED' -or $stale) {
                if (Test-GhprDirty -Dir $dir) {
                    $skipped += [pscustomobject]@{ Name = $name; Info = "$state $repoSlug#$prNumber (uncommitted changes or stashes)" }
                }
                else {
                    $toDelete += [pscustomobject]@{ Dir = $dir; Name = $name; Slug = $repoSlug; Pr = $prNumber; State = $state; Title = $title }
                }
            }
            else {
                $kept += [pscustomobject]@{ Name = $name; Info = "$state $repoSlug#$prNumber" }
            }
        }

    # ----- Report -----
    $deleteLabel = if ($Days -gt 0) { "PR merged/closed or not modified for $Days+ days" } else { 'PR merged/closed' }

    Write-Host ""
    if ($toDelete.Count -gt 0) {
        Write-Host "To delete ($deleteLabel):"
        foreach ($c in $toDelete) {
            Write-Host ("  [{0}] {1,-40} {2} #{3}  {4}" -f $c.State, $c.Name, $c.Slug, $c.Pr, $c.Title)
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

function ghpr {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$First,

        [Parameter(Position = 1)]
        [string]$Second,

        [switch]$DryRun,
        [switch]$Yes,
        [int]$Days = 0
    )

    $usage = @"
Usage:
  ghpr <pr-number> <owner/repo>
  ghpr <github-pr-url>
  ghpr clean [-DryRun] [-Yes] [-Days <N>]

Examples:
  ghpr 125 octocat/Hello-World
  ghpr https://github.com/octocat/Hello-World/pull/125
  ghpr clean            # remove work dirs whose PR is merged/closed
  ghpr clean -DryRun    # list candidates without deleting
"@

    $baseDir = Join-Path $HOME "work\prs"

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
