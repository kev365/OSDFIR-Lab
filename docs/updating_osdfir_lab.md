# Updating OSDFIR Lab

This document outlines how to use the `update-osdfir-lab.ps1` script to update your local OSDFIR Lab Helm charts to the latest version.

## Overview

The update script automates the process of fetching the latest release of the `osdfir-infrastructure` charts from GitHub, backing up your current project, and applying the updates. It also reapplies any custom configurations you have stored.

## Current version baseline (November 2025)

These are the versions currently pinned in the lab configuration. Review the upstream release notes before changing them.

- **OSDFIR infrastructure chart**: `2.5.6` ([release notes](https://github.com/google/osdfir-infrastructure/releases/tag/osdfir-infrastructure-2.5.6)).
- **Timesketch**: `20251114` image with supporting services `nginx:1.25.5-alpine-slim`, `opensearchproject/opensearch:3.1.0`, `opensearchproject/opensearch-dashboards:3.1.0`, `redis:7.4.2-alpine`, and `postgres:17.5-alpine` ([release notes](https://github.com/google/timesketch/releases/tag/20251114)).
- **OpenRelik**: core components `0.6.0` ([server release](https://github.com/openrelik/openrelik-server/releases/tag/0.6.0)) with workers pinned to `openrelik-worker-analyzer-config:0.2.0`, `openrelik-worker-plaso:0.4.0`, `openrelik-worker-timesketch:0.3.0`, `openrelik-worker-hayabusa:0.3.0`, and `openrelik-worker-extraction:0.5.0`.
- **Prometheus (OpenRelik)**: `prom/prometheus:v3.0.1`.
- **LLM model**: `smollm:latest` served through Ollama. Confirm model availability with `ollama pull smollm:latest` if you rebuild the cache.

If upstream releases introduce new dependency versions, update `configs/osdfir-lab-values.yaml`, `terraform/variables.tf`, and the Ollama deployment templates together to keep the stack consistent.

## Post-update verification checklist

After bumping versions, validate the deployment before promoting the changes:

- Run `helm template` or `helm lint` against the updated values to catch obvious YAML issues.
- Execute `terraform plan` to confirm the chart upgrade (`osdfir_chart_version`) and value overrides apply cleanly.
- Once deployed, run `.\scripts\manage-osdfir-lab.ps1 status` followed by `ollama-test` to confirm the new LLM model responds.
- Verify Timesketch AI features by requesting an NL2Q query and an event summary; both should report `smollm:latest` as the active provider.

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
