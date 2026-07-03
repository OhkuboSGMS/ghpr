#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the ghpr GitHub PR checkout tool for PowerShell (Windows).
.DESCRIPTION
    Copies ghpr.ps1 to ~\.local\bin and adds a dot-source line to your
    PowerShell profile so the `ghpr` function is available in every session.
#>

$ErrorActionPreference = 'Stop'

# Run from the directory of this script so the relative copy works regardless of cwd.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

Write-Host "Installing ghpr tool..."

# Check if gh is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Error: GitHub CLI (gh) is not installed" -ForegroundColor Red
    Write-Host "Please install it from: https://cli.github.com/  (or: winget install GitHub.cli)"
    exit 1
}

# Create install directory
$binDir = Join-Path $HOME ".local\bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
}

# Copy the function file
$target = Join-Path $binDir "ghpr.ps1"
Write-Host "Copying ghpr.ps1 to $target..."
Copy-Item -Path (Join-Path $scriptDir "ghpr.ps1") -Destination $target -Force

# Determine BOTH edition profile paths (PowerShell 7 and Windows PowerShell 5.1)
# so `ghpr` works no matter which one the user launches. Derive the sibling path
# from the current $PROFILE so OneDrive-redirected Documents folders are handled.
if ($PROFILE -match 'WindowsPowerShell') {
    $ps51Profile = $PROFILE
    $ps7Profile  = $PROFILE -replace '\\WindowsPowerShell\\', '\PowerShell\'
}
else {
    $ps7Profile  = $PROFILE
    $ps51Profile = $PROFILE -replace '\\PowerShell\\', '\WindowsPowerShell\'
}

$sourceLine = ". `"$target`""
$marker = "# ghpr: GitHub PR checkout tool"

function Add-GhprToProfile {
    param([string]$ProfilePath)

    $dir = Split-Path -Parent $ProfilePath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    if (-not (Test-Path $ProfilePath)) {
        New-Item -ItemType File -Force -Path $ProfilePath | Out-Null
        Write-Host "Created PowerShell profile: $ProfilePath"
    }

    $content = Get-Content -Path $ProfilePath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { $content = "" }

    if ($content -match [regex]::Escape("ghpr.ps1")) {
        Write-Host "ghpr already present in $ProfilePath, skipping..." -ForegroundColor Yellow
    }
    else {
        Write-Host "Adding ghpr to $ProfilePath..."
        Add-Content -Path $ProfilePath -Value "`r`n$marker`r`n$sourceLine"
        Write-Host "Added ghpr to $ProfilePath" -ForegroundColor Green
    }
}

Add-GhprToProfile -ProfilePath $ps7Profile
Add-GhprToProfile -ProfilePath $ps51Profile

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "To start using ghpr:"
Write-Host "  1. Reload your profile:  . `$PROFILE   (or open a new terminal)"
Write-Host "  2. Try: ghpr <pr-number> <owner/repo>"
Write-Host "  3. Or:  ghpr https://github.com/owner/repo/pull/<number>"
Write-Host ""
Write-Host "Note: if scripts are blocked, you may need to allow them once:"
Write-Host "  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
