#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls the ghpr GitHub PR checkout tool from PowerShell (Windows).
#>

$ErrorActionPreference = 'Stop'

Write-Host "Uninstalling ghpr tool..."

# Remove the function file
$target = Join-Path $HOME ".local\bin\ghpr.ps1"
if (Test-Path $target) {
    Write-Host "Removing $target..."
    Remove-Item -Force $target
    Write-Host "Removed ghpr.ps1" -ForegroundColor Green
}
else {
    Write-Host "ghpr.ps1 not found" -ForegroundColor Yellow
}

# Remove the dot-source line from BOTH edition profiles (PowerShell 7 and
# Windows PowerShell 5.1), since install adds it to both.
if ($PROFILE -match 'WindowsPowerShell') {
    $ps51Profile = $PROFILE
    $ps7Profile  = $PROFILE -replace '\\WindowsPowerShell\\', '\PowerShell\'
}
else {
    $ps7Profile  = $PROFILE
    $ps51Profile = $PROFILE -replace '\\PowerShell\\', '\WindowsPowerShell\'
}

function Remove-GhprFromProfile {
    param([string]$ProfilePath)

    if (-not (Test-Path $ProfilePath)) { return }
    $lines = Get-Content -Path $ProfilePath
    if (-not ($lines -match "ghpr.ps1")) { return }

    Write-Host "Removing ghpr from $ProfilePath..."

    # Backup
    $backup = "$ProfilePath.ghpr.bak"
    Copy-Item -Path $ProfilePath -Destination $backup -Force

    # Drop the marker comment line and any line that sources ghpr.ps1
    $filtered = $lines | Where-Object {
        ($_ -notmatch "# ghpr: GitHub PR checkout tool") -and ($_ -notmatch "ghpr\.ps1")
    }
    Set-Content -Path $ProfilePath -Value $filtered

    Write-Host "Removed ghpr from $ProfilePath" -ForegroundColor Green
    Write-Host "Backup saved to $backup" -ForegroundColor Yellow
}

Remove-GhprFromProfile -ProfilePath $ps7Profile
Remove-GhprFromProfile -ProfilePath $ps51Profile

Write-Host ""
Write-Host "Note: PR work directories in ~\work\prs\ were not removed" -ForegroundColor Yellow
Write-Host "To clean them up manually, run:"
Write-Host "  Remove-Item -Recurse -Force `$HOME\work\prs"
Write-Host ""
Write-Host "Uninstallation complete!" -ForegroundColor Green
Write-Host "Please reload your profile or start a new terminal session."
