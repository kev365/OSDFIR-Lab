# Updating OSDFIR Lab

This document covers how components in the lab are versioned and updated. Most
of the work is now automated; the "how do I bump everything?" answer is
usually "pull `main` and redeploy."

## How updates flow

### Automatic

| What | How it updates | Notes |
| ---- | -------------- | ----- |
| `osdfir-infrastructure` Helm chart | Weekly GitHub Action (`.github/workflows/check-chart-version.yml`) | Opens an auto-merging PR that bumps `terraform/variables.tf`, `README.md`, and prepends a line under `## [Unreleased]` in `CHANGELOG.md`. Requires "Allow auto-merge" enabled in repo Settings. |
| **All upstream component images** — Timesketch, OpenSearch, OpenSearch Dashboards, OpenRelik core (frontend / api / mediator / metrics), OpenRelik workers, Yeti, HashR, Prometheus, Redis, Postgres, nginx | Chart-managed | We do NOT override these in `configs/osdfir-lab-values.yaml`. Each chart release pins a coherent set of image tags; a chart bump brings all of them along. |
| OpenRelik worker images on `:latest` tag | Helm `imagePullPolicy: IfNotPresent` | New tags are picked up on pod restart. Force a refresh with `kubectl rollout restart deployment/osdfir-lab-openrelik-worker-<name> -n osdfir`. |
| Ollama container | `:latest` image tag | To force-pull a newer image: `kubectl rollout restart deployment/ollama -n osdfir` (see [terraform/ollama.tf](../terraform/ollama.tf)). |

### Manual

Only a few knobs in [configs/osdfir-lab-values.yaml](../configs/osdfir-lab-values.yaml) require conscious edits:

- **Our own worker catalog** — the `openrelik.workers` list includes every known worker with an `enabled` flag. Toggle workers via `manage-openrelik-workers.ps1` (or the `deploy -Enable/-Disable` flags); see the [Workers](#workers-the-openrelikworkers-list) section below.
- **LLM model wiring** — `ai.model.name`, `openrelik.config.analyzers.llm.model`, `LLM_MODEL_NAME` on the `openrelik-worker-llm` entry, and the Timesketch `timesketch.conf` file. See [Changing the LLM model](#changing-the-llm-model).
- **Enable/disable a whole subchart** — `global.<tool>.enabled: true/false` for Timesketch, OpenRelik, Yeti, HashR, GRR.
- **Ollama variables** — `terraform/variables.tf` has `deploy_ollama`, `ai_model_name`, `enable_ollama_vulkan` toggles.

After any manual edit, redeploy:

```powershell
./scripts/manage-osdfir-lab.ps1 deploy
```

Terraform picks up the changed values file, runs `helm upgrade`, and Helm
rolls Deployments forward one at a time.

### If you need to pin or override

If a chart release ships an image you can't use (regression, missing tag in
your registry, etc.) you can still override by adding a block to
`osdfir-lab-values.yaml`. For example to pin OpenSearch to a specific tag:

```yaml
timesketch:
  opensearch:
    image:
      repository: opensearchproject/opensearch
      tag: "3.1.0"
```

The chart's structure (`timesketch.opensearch.image.tag`, `openrelik.api.image.tag`, etc.) is documented in the upstream chart's `values.yaml` — run `helm show values osdfir-charts/osdfir-infrastructure --version <ver>` to see every knob.

## Workers (the openrelik.workers list)

The worker catalog lives inline at `openrelik.workers` in
[configs/osdfir-lab-values.yaml](../configs/osdfir-lab-values.yaml). Each entry
carries its own `enabled`, `description`, `source` fields next to
`image`/`command`. To enable or disable a worker:

```powershell
# Flip a catalog entry and scale an existing Deployment in one call:
./scripts/manage-openrelik-workers.ps1 enable plaso
./scripts/manage-openrelik-workers.ps1 disable hayabusa

# See the full set (47 workers, 21 official + 26 community):
./scripts/manage-openrelik-workers.ps1 list

# Bulk-enable at deploy time instead of pre-edit:
./scripts/manage-osdfir-lab.ps1 deploy -Enable "plaso,yara,mftecmd" -Disable "strings"
```

[scripts/manage-osdfir-lab.ps1](../scripts/manage-osdfir-lab.ps1)'s
`Build-WorkerOverride` filters the full list to only the entries with
`enabled: true` and a non-empty `image`, and hands that subset to Helm. So
disabled workers never create a Deployment.

## Changing the LLM model

Four places to update, then a restart sequence. All file paths are relative to
the repo root.

1. **[configs/osdfir-lab-values.yaml](../configs/osdfir-lab-values.yaml)** — `ai.model.name`, `openrelik.config.analyzers.llm.model`, and the `LLM_MODEL_NAME` env var on the `openrelik-worker-llm` worker entry.
2. **[terraform/variables.tf](../terraform/variables.tf)** — `ai_model_name` default value.
3. **configs/timesketch/timesketch.conf** — `LLM_PROVIDER_CONFIGS` dict (three entries: `nl2q`, `llm_summarize`, `default`). After editing, rebuild the tarball that terraform's config map reads from.
4. **Restart sequence** after `./scripts/manage-osdfir-lab.ps1 deploy`:

   ```powershell
   kubectl rollout restart deployment/ollama -n osdfir
   kubectl rollout restart deployment/osdfir-lab-timesketch -n osdfir
   kubectl rollout restart deployment/osdfir-lab-timesketch-worker -n osdfir
   kubectl rollout restart deployment/osdfir-lab-openrelik-worker-llm -n osdfir
   ```

## Enabling Vulkan GPU acceleration

Ollama supports experimental GPU acceleration via the [Vulkan](https://github.com/ollama/ollama/blob/main/docs/gpu.md)
graphics API. Only useful if the Kubernetes node has a GPU passed through. In
a standard Minikube-on-laptop setup, leave it disabled.

To enable: set `enable_ollama_vulkan = true` in
[terraform/variables.tf](../terraform/variables.tf), run
`./scripts/manage-osdfir-lab.ps1 deploy`, then:

```powershell
kubectl rollout restart deployment/ollama -n osdfir
```

## MCP Servers

[MCP (Model Context Protocol)](https://modelcontextprotocol.io/) servers expose
AI tool interfaces to the forensic platforms. Each server is deployed as its
own Kubernetes pod and toggled via a boolean in
[terraform/variables.tf](../terraform/variables.tf).

| Server | Variable | Port | Image |
| ------ | -------- | ---- | ----- |
| Timesketch MCP | `deploy_timesketch_mcp` | 8081 | `ghcr.io/<owner>/timesketch-mcp-server:latest` (built by [.github/workflows/build-mcp-servers.yml](../.github/workflows/build-mcp-servers.yml)) |
| OpenRelik MCP | `deploy_openrelik_mcp` | 7070 | `ghcr.io/openrelik/openrelik-mcp-server:latest` (upstream) |
| Yeti MCP | `deploy_yeti_mcp` | 8082 | `ghcr.io/<owner>/yeti-mcp-server:latest` (built by the same workflow) |

### Enabling an MCP server

1. Flip the corresponding variable to `true` in [terraform/variables.tf](../terraform/variables.tf).
2. Run `./scripts/manage-osdfir-lab.ps1 deploy`.
3. Run `./scripts/manage-osdfir-lab.ps1 mcp-setup` — it walks you through supplying API keys for the OpenRelik / Yeti MCPs (Timesketch reuses the existing Timesketch secret, so no extra key needed).

### MCP server sources

- **Timesketch**: <https://github.com/timesketch/timesketch-mcp-server>
- **OpenRelik**: <https://github.com/openrelik/openrelik-mcp-server>
- **Yeti**: <https://github.com/yeti-platform/yeti-mcp>

## Verification checklist after an update

- `./scripts/manage-osdfir-lab.ps1 status` — all pods Running / 1/1.
- `./scripts/manage-osdfir-lab.ps1 logs` — reports no problem pods.
- `./scripts/manage-osdfir-lab.ps1 creds` — Timesketch and OpenRelik appear, `admin`/`admin` logins work.
- `./scripts/manage-osdfir-lab.ps1 ollama` — pod Running, model listed, sample prompts return text.
- If Yeti or HashR are enabled, confirm their pods come up (they're off by default).
- If the update touched `osdfir_chart_version`, check `CHANGELOG.md` — the auto-update workflow appends a line with the upstream release URL so you can skim the upstream release notes before merging.

## Historical note

Earlier versions of the repo shipped a separate `scripts/update-osdfir-lab.ps1`
that downloaded chart release tarballs and applied custom patches from
`configs/update/`. That flow is gone — chart upgrades now happen through
Helm directly (via Terraform) using versioned pulls from the chart repo.
