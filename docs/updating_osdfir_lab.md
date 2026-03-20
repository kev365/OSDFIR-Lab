# Updating OSDFIR Lab

This document outlines how to use the `update-osdfir-lab.ps1` script to update your local OSDFIR Lab Helm charts to the latest version.

## Overview

The update script automates the process of fetching the latest release of the `osdfir-infrastructure` charts from GitHub, backing up your current project, and applying the updates. It also reapplies any custom configurations you have stored.

## Current version baseline (March 2026)

These are the versions currently pinned in the lab configuration. Review the upstream release notes before changing them.

- **OSDFIR infrastructure chart**: `2.8.4` ([release notes](https://github.com/google/osdfir-infrastructure/releases/tag/osdfir-infrastructure-2.8.4)).
- **Timesketch**: `20260311` image with supporting services `nginx:1.25.5-alpine-slim`, `opensearchproject/opensearch:3.1.0`, `opensearchproject/opensearch-dashboards:3.1.0`, `redis:7.4.2-alpine`, and `postgres:17.5-alpine` ([release notes](https://github.com/google/timesketch/releases/tag/20260311)).
- **OpenRelik**: core components `0.7.0` ([server release](https://github.com/openrelik/openrelik-server/releases/tag/0.7.0)) with workers pinned to `openrelik-worker-analyzer-config:0.2.0`, `openrelik-worker-plaso:0.5.0`, `openrelik-worker-timesketch:0.3.0`, `openrelik-worker-hayabusa:0.3.0`, and `openrelik-worker-extraction:0.6.0`.
- **Yeti**: frontend/api `2.5.0`, `redis:7.4.2-alpine`, `arangodb:3.11.8`. Yeti UI accessible at `http://localhost:9999`.
- **HashR**: `v1.8.2`, `postgres:17.2-alpine`.
- **Prometheus (OpenRelik)**: `prom/prometheus:v3.10.0`.
- **LLM model**: `smollm:latest` served through Ollama. Confirm model availability with `ollama pull smollm:latest` if you rebuild the cache.

If upstream releases introduce new dependency versions, update `configs/osdfir-lab-values.yaml`, `terraform/variables.tf`, and the Ollama deployment templates together to keep the stack consistent.

## Post-update verification checklist

After bumping versions, validate the deployment before promoting the changes:

- Run `helm template` or `helm lint` against the updated values to catch obvious YAML issues.
- Execute `terraform plan` to confirm the chart upgrade (`osdfir_chart_version`) and value overrides apply cleanly.
- Once deployed, run `.\scripts\manage-osdfir-lab.ps1 status` followed by `ollama-test` to confirm the new LLM model responds.
- Verify Timesketch AI features by requesting an NL2Q query and an event summary; both should report `smollm:latest` as the active provider.
- Confirm Yeti is accessible at `http://localhost:9999` and credentials are returned by `.\scripts\manage-osdfir-lab.ps1 creds`.
- Confirm HashR pod is running via `.\scripts\manage-osdfir-lab.ps1 status`.
- Verify Timesketch analyzers list includes the Yeti threat-intel and HashR lookup analyzers.

## Changing the LLM model

The model name is set in four places. Update all of them, then restart the affected pods.

1. **`configs/osdfir-lab-values.yaml`** — `ai.model.name`, `openrelik.config.analyzers.llm.model`, and the `LLM_MODEL_NAME` env var on the `openrelik-worker-llm` worker entry.
2. **`terraform/variables.tf`** — `ai_model_name` default value.
3. **`configs/timesketch/timesketch.conf`** — `LLM_PROVIDER_CONFIGS` dict (three entries: `nl2q`, `llm_summarize`, `default`). After editing, rebuild the tarball with `./tools/build-ts-configs.sh`.
4. **Restart sequence** — Run `terraform apply`, then:
   ```powershell
   kubectl rollout restart deployment/ollama -n osdfir
   kubectl rollout restart deployment/osdfir-lab-timesketch-web -n osdfir
   kubectl rollout restart deployment/osdfir-lab-timesketch-worker -n osdfir
   kubectl rollout restart deployment/osdfir-lab-openrelik-worker-llm -n osdfir
   ```

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
