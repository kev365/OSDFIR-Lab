<#
.SYNOPSIS
  OSDFIR Lab Update Script

.DESCRIPTION
  Backs up (unless -NoBackup) and updates the OSDFIR Lab Helm charts to the latest release from GitHub.
  Fetches the latest release via GitHub API, cleans out the 'helm' folder, extracts the new charts,
  applies any local custom patches from configs/update, and preserves the configs folder.
  Use -DryRun for a safe simulation. Prints backup and release info.

.EXAMPLE
  .\update-osdfir-lab.ps1 -Force

.NOTES
  Run this script from within the scripts directory of your OSDFIR Lab project.
#>

param(
    [Switch]$Force,
    [Switch]$NoBackup,
    [Switch]$DryRun,
    [Switch]$h,        # alias for help
    [Switch]$Help
)

# Color constants for output
$Colors = @{
    Header    = "Cyan"
    Success   = "Green"
    Warning   = "Yellow"
    Error     = "Red"
    Info      = "White"
    Gray      = "Gray"
}

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "== $Title ==" -ForegroundColor $Colors.Header
    Write-Host ("=" * ($Title.Length + 7)) -ForegroundColor $Colors.Header
}

function Apply-Custom-Patches {
    param($ProjectDir)
    Show-Header "Applying Custom Configuration Patches"
    $sourceDir = Join-Path $ProjectDir "configs\update"
    $destDir = $ProjectDir

    if (-not (Test-Path $sourceDir)) {
        Write-Host "No custom patch directory found at '$sourceDir', skipping." -ForegroundColor $Colors.Gray
        return
    }

    Write-Host "Applying patches from '$sourceDir' to project root..." -ForegroundColor $Colors.Info
    try {
        if (-not $DryRun) {
            Copy-Item -Path "$sourceDir\*" -Destination $destDir -Recurse -Force
            Write-Host "[OK] Custom patches applied successfully." -ForegroundColor $Colors.Success
        } else {
            Write-Host "DRY RUN: Would apply patches from '$sourceDir' to project root." -ForegroundColor $Colors.Gray
        }
    } catch {
        Write-Host "[ERROR] Failed to apply custom patches: $($_.Exception.Message)" -ForegroundColor $Colors.Error
    }
}

# Show help if -h or -Help is invoked
if ($h -or $Help) {
    Write-Host "== OSDFIR Lab Update Tool =="
    Write-Host "============================"
    Write-Host "Usage: .\update-osdfir-lab.ps1 [options]"
    Write-Host ""
    Write-Host "This script backs up the current OSDFIR Lab project and updates the Helm charts to the latest version."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -h         Show help (alias: -Help)"
    Write-Host "  -Force     Run without confirmation prompts"
    Write-Host "  -NoBackup  Skip the backup step"
    Write-Host "  -DryRun    Don't make any changes, just print intended actions"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\update-osdfir-lab.ps1"
    Write-Host "  .\update-osdfir-lab.ps1 -Force -NoBackup"
    return
}

# == Preflight checks ==
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Write-Error "'tar' is required but was not found in PATH. Please install tar before running this script."
    return
}
if (-not (Get-Command Invoke-RestMethod -ErrorAction SilentlyContinue)) {
    Write-Error "'Invoke-RestMethod' is required but not found. Please update your PowerShell version."
    return
}

# Get script and project directory paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = "." }
# Assume project root is one level up from scripts folder
$ProjectDir = Split-Path -Parent $ScriptDir
Write-Host "============================"
Write-Host "NOTE: To ensure a complete backup, please close any applications that might be using project files (such as Terraform, VSCode, or Docker Desktop) before proceeding."
Write-Host "If any files are in use or locked, they may not be included in the backup and will be listed."
Write-Host "============================"

# Flexible confirmation prompt if -Force not used
if (-not $Force) {
    Write-Host "This will back up the current OSDFIR Lab project and apply the latest updates to the Helm charts."
    while ($true) {
        $confirmation = Read-Host "Continue? (Y/N)"
        $confirmation = $confirmation.Trim().ToLower()
        if ($confirmation -in @('y','yes')) {
            break  # proceed
        } elseif ($confirmation -in @('n','no')) {
            Write-Host "Update canceled by user."
            return
        } else {
            Write-Host "Please enter Y, N, Yes, or No."
        }
    }
}

# 1. Backup current project to a zip file in 'backups' folder (unless -NoBackup or -DryRun)
$backupZip = $null
$failedFiles = @()
if (-not $NoBackup -and -not $DryRun) {
    Write-Host "Creating project backup..."
    $backupFolder = Join-Path $ProjectDir "backups"
    if (-not (Test-Path $backupFolder)) {
        New-Item -Path $backupFolder -ItemType Directory | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupZip = Join-Path $backupFolder ("osdfir-lab-backup-$timestamp.zip")
    $items = Get-ChildItem -Path $ProjectDir -Force -Exclude 'backups'
    if ($items.Count -eq 0) {
        Write-Warning "No files found to backup (project directory may be empty)."
    } else {
        try {
            Compress-Archive -Path $items -DestinationPath $backupZip -Force -ErrorAction Stop
            Write-Host "Backup created at: $backupZip"
        } catch {
            Write-Warning "Some files could not be backed up (they may be open or locked):"
            # Try to parse the error for the locked file(s)
            $lockedMsg = $_.Exception.Message
            Write-Host $lockedMsg -ForegroundColor Yellow
            # Try to extract filename(s) if possible and add to failedFiles array
            if ($lockedMsg -match "'([^']+)'") {
                $failedFiles += $Matches[1]
            }
        }
    }
} elseif ($NoBackup) {
    Write-Host "Backup step skipped due to -NoBackup option."
} elseif ($DryRun) {
    Write-Host "DRY RUN: Would create a backup of the project here."
}

if ($failedFiles.Count -gt 0) {
    Write-Host "`nWarning: The following files could not be backed up due to being open or locked:"
    foreach ($file in $failedFiles) {
        Write-Host " - $file"
    }
}

# 2. Download the latest OSDFIR Infrastructure charts release using GitHub API
$apiUrl = "https://api.github.com/repos/google/osdfir-infrastructure/releases/latest"
try {
    $apiHeaders = @{ "User-Agent" = "Mozilla/5.0" }
    $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers $apiHeaders -ErrorAction Stop
    $latestVersion = $releaseInfo.tag_name -replace "^osdfir-infrastructure-", ""
    Write-Host "Latest OSDFIR Infrastructure release is: $latestVersion"
} catch {
    Write-Error "Failed to retrieve latest release info from GitHub API: $($_.Exception.Message)"
    return
}

$releaseURL   = "https://github.com/google/osdfir-infrastructure/releases/download/osdfir-infrastructure-$latestVersion/osdfir-infrastructure-$latestVersion.tgz"
$downloadFile = Join-Path $([IO.Path]::GetTempPath()) "osdfir-infra-update.tgz"
Write-Host "Downloading OSDFIR Infrastructure charts v$latestVersion ..."
if (-not $DryRun) {
    try {
        Invoke-WebRequest -Uri $releaseURL -OutFile $downloadFile -ErrorAction Stop
        Write-Host "Downloaded update package to $downloadFile"
    }
    catch {
        Write-Error "Failed to download update package. Please check your internet connection or the release URL."
        return
    }
} else {
    Write-Host "DRY RUN: Would download from $releaseURL"
}

# 3. Extract the downloaded package into the helm folder
$helmFolder = Join-Path $ProjectDir "helm"
if (-not (Test-Path $helmFolder)) {
    Write-Error "Helm folder not found at $helmFolder. Aborting update."
    return
}

Write-Host "Cleaning out helm folder contents before update..."
if (-not $DryRun) {
    Get-ChildItem -Path $helmFolder -Force | Remove-Item -Recurse -Force
    Write-Host "Helm folder cleared."
} else {
    Write-Host "DRY RUN: Would clean out helm folder contents before update."
}

Write-Host "Extracting update package into helm directory..."
if (-not $DryRun) {
    try {
        tar -xzf $downloadFile -C $helmFolder --strip-components=1
        Write-Host "Update package extracted."
    }
    catch {
        Write-Error "Extraction failed. Ensure that 'tar' is available on this system."
        return
    }
    # Clean up the downloaded archive file
    Remove-Item $downloadFile -Force
} else {
    Write-Host "DRY RUN: Would extract update package into helm directory."
}

# 4. Apply custom patches to the updated chart files
Apply-Custom-Patches -ProjectDir $ProjectDir

Write-Host "`n== OSDFIR Lab update complete =="
Write-Host "Charts updated to version: $latestVersion"
if ($backupZip) { Write-Host "Project backup file: $backupZip" }
Write-Host "You can now deploy or upgrade your lab to apply the new chart changes."
Write-Host "============================"