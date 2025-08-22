# Updating OSDFIR Lab

This document outlines how to use the `update-osdfir-lab.ps1` script to update your local OSDFIR Lab Helm charts to the latest version.

## Overview

The update script automates the process of fetching the latest release of the `osdfir-infrastructure` charts from GitHub, backing up your current project, and applying the updates. It also reapplies any custom configurations you have stored.

## Usage

To run the update script, open a PowerShell terminal, navigate to the project root directory, and execute the following command:

```powershell
.\scripts\update-osdfir-lab.ps1
```

### Parameters

You can modify the script's behavior using the following optional parameters:

-   `-Force`: Skips the confirmation prompt and runs the script non-interactively.
-   `-NoBackup`: Disables the automatic backup of the project directory.
-   `-DryRun`: Performs a "dry run" of the update process. It will show you what actions would be taken without actually making any changes to your files.
-   `-Help`: Displays the help message for the script.

### Example

To run the update without any interactive prompts:

```powershell
.\scripts\update-osdfir-lab.ps1 -Force
```

## Update Process

The script performs the following steps:

1.  **Backup**: Creates a `.zip` backup of the entire project directory (except for the `backups` folder itself) and stores it in the `backups/` directory. This can be skipped with the `-NoBackup` flag.
2.  **Fetch Latest Release**: Connects to the GitHub API to find the latest release of the `google/osdfir-infrastructure` repository.
3.  **Download & Extract**: Downloads the latest release package (`.tgz`), clears the contents of the local `helm/` directory, and extracts the new charts into it.
4.  **helm-addons**: Leave templates in `helm-addons/` untouched; use values in `configs/osdfir-lab-values.yaml` to customize behavior.
5.  **Apply Custom Patches**: Copies any custom configuration files from `configs/update/` into the project, overwriting the newly updated files. This ensures your local modifications are preserved.
