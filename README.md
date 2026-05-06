
![Version](https://img.shields.io/badge/version-20260419-orange)
![GitHub forks](https://img.shields.io/github/forks/kev365/OSDFIR-Lab?style=social) 
![GitHub stars](https://img.shields.io/github/stars/kev365/OSDFIR-Lab?style=social) 
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

# OSDFIR Lab

**Version:** 20260419

A test lab environment for deploying Open Source Digital Forensics and Incident Response (OSDFIR) tools in a Minikube environment with integrated AI capabilities using Docker Desktop.

- Source project: https://github.com/google/osdfir-infrastructure

## Overview

This repository provides a complete lab setup for OSDFIR tools running on Kubernetes via Minikube. It includes automated deployment scripts, AI integration experiments, and a unified management interface for easy testing and development.

## Project Structure

```text
osdfir-lab/
├── .github/workflows/      # GitHub Actions (MCP image builds, chart auto-update)
├── configs/                # Helm values (incl. the worker catalog), Timesketch configs, MCP sources
├── docs/                   # Contributor + maintenance docs
├── helm-addons/            # Add-on Helm templates (Timesketch LLM config tarball source)
├── scripts/                # manage-osdfir-lab.ps1, manage-openrelik-workers.ps1
└── terraform/              # Namespace, PVCs, helm_release, Ollama, MCP server deployments
```

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) with Kubernetes & WSL2 backend enabled
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [Terraform](https://www.terraform.io/downloads)
- [Windows PowerShell](https://docs.microsoft.com/en-us/powershell/) with execution policy set:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
  ```

### Example Development Environment

*This lab has been developed and tested on the following setup (your mileage may vary):*

**Hardware:**
- CPU: Modern multi-core processor (8+ logical cores recommended)
- RAM: 16GB+ system memory
- Storage: 100GB+ available SSD disk space

**Software:**
- Windows 11 Pro with WSL2 enabled with Ubuntu
- Docker Desktop for Windows
  - Memory allocation: 8GB+
  - WSL2 integration enabled
- PowerShell 5.1+

**Minikube Configuration (auto-detected by script):**
- Driver: `docker`
- Memory: 75% of Docker Desktop's available memory (minimum 8GB)
- CPUs: 50% of system logical processors (minimum 8, maximum 12)
- Disk: 40GB
- Kubernetes version: stable

## Installation

Clone (or fork) the repository — `main` tracks the latest tested state. There are no tagged releases; pull the latest `main` and redeploy when you want updates.

```bash
git clone https://github.com/kev365/OSDFIR-Lab.git
cd OSDFIR-Lab
```

See [CHANGELOG.md](CHANGELOG.md) for notable changes.

## Quick Start

### One-Command Deployment

Open PowerShell as **Administrator** and run:

```powershell
./scripts/manage-osdfir-lab.ps1 deploy
```

This automatically handles:
- Docker Desktop startup
- Minikube cluster creation with optimal resource allocation
- Terraform infrastructure deployment
- Service port forwarding

### Access Your Lab

Default login for every tool: **`admin` / `admin`** (static lab credentials — see Disclaimer).

```powershell
# Check status
./scripts/manage-osdfir-lab.ps1 status

# Show login credentials
./scripts/manage-osdfir-lab.ps1 creds

# Manage OpenRelik workers (enable/disable individual workers)
./scripts/manage-openrelik-workers.ps1 list
./scripts/manage-openrelik-workers.ps1 enable plaso

# Services that are deployed by default:
# - Timesketch:         http://localhost:5000
# - OpenRelik:          http://localhost:8711
# - OpenRelik API:      http://localhost:8710
#
# Opt-in services (enable via values.yaml, then redeploy):
# - Yeti:                  http://localhost:9000                 (global.yeti.enabled: true)
# - HashR:                 backend only, no UI                   (global.hashr.enabled: true)
# - OpenSearch Dashboards: http://localhost:5000/opensearch      (timesketch.opensearch.selfSigned: true + dashboard.ingress: true)
```

### Cleanup

```powershell
# Clean shutdown, preserves AI models and data for a fast redeploy:
./scripts/manage-osdfir-lab.ps1 shutdown-lab

# Nuclear option - wipes the Minikube cluster, AI models, and all data:
./scripts/manage-osdfir-lab.ps1 destroy-lab
```

## Components

### Core OSDFIR Tools

- **[Timesketch](https://timesketch.org/)** - Timeline analysis and collaborative investigation
- **[OpenRelik](https://openrelik.org/)** - Evidence processing and workflow automation  
- **[HashR](https://osdfir.blogspot.com/2024/03/introducing-hashr.html)** - Hash verification and analysis
- **[Yeti](https://yeti-platform.io/)** - Threat intelligence platform

### Infrastructure

- **Minikube** - Local Kubernetes cluster
- **Terraform** - Infrastructure as Code
- **Helm** - Package management (pulls upstream `osdfir-infrastructure` chart)
- **Docker Desktop** - Container runtime

### Component Versions

- `osdfir-infrastructure` Helm chart: **2.8.8** (auto-bumped by [.github/workflows/check-chart-version.yml](.github/workflows/check-chart-version.yml))
- **Timesketch, OpenSearch (+ Dashboards), OpenRelik core + workers, Yeti, HashR, Prometheus, Redis, Postgres, nginx**: all tags come from the upstream chart. The values.yaml in this repo does not pin any of them, so a chart bump rolls every component forward at once.
- Ollama image: **latest** (pinned via `terraform/ollama.tf`)
- Ollama model: `qwen2.5:0.5b` (configurable via `terraform/variables.tf`)

The weekly chart-version workflow opens an auto-merging PR when an upstream chart update is available and appends the bump to [CHANGELOG.md](CHANGELOG.md). See [docs/updating_osdfir_lab.md](docs/updating_osdfir_lab.md) for what's automatic vs manual and how to override a chart-pinned image if needed.

## 🚧 Work in Progress

### AI Integration (Experimental)

- **Ollama Server** - Local AI model hosting. Default model is `qwen2.5:0.5b` (intentionally tiny so the lab runs on a laptop). Swap for a bigger model in [terraform/variables.tf](terraform/variables.tf) `ai_model_name` when you have the headroom.
- **Timesketch LLM Features** - Natural Language to Query (NL2Q) + Event Summarization (working on larger models; small-model responses can time out).
- **OpenRelik LLM Worker** - enable the `llm` worker in the catalog to route analyzer tasks through Ollama.
- **Timesketch MCP Server** - prebuilt via GitHub Actions, deployable via Terraform toggle (`deploy_timesketch_mcp`).
- **OpenRelik MCP Server** - uses upstream image, deployable via Terraform toggle (`deploy_openrelik_mcp`).
- **Yeti MCP Server** - prebuilt via GitHub Actions, deployable via Terraform toggle (`deploy_yeti_mcp`).

**Current Status:**

- Basic integration working; extended prompt testing runs via `./scripts/manage-osdfir-lab.ps1 ollama`.
- The default model is small and may time out on more complex prompts. Point Ollama at a larger model (or an external LLM) for better results.

## Management

Two scripts, one responsibility each.

```powershell
# All day-to-day operations:
./scripts/manage-osdfir-lab.ps1 [action]

# Key actions: deploy, status, start/stop, creds, logs, ollama,
# shutdown-lab (clean), destroy-lab (nuclear), mcp-setup
./scripts/manage-osdfir-lab.ps1 help         # full list + descriptions
```

```powershell
# OpenRelik worker toggles (47 workers, 2 enabled by default):
./scripts/manage-openrelik-workers.ps1 list
./scripts/manage-openrelik-workers.ps1 enable plaso
./scripts/manage-openrelik-workers.ps1 disable hayabusa
```

You can also toggle workers during a deploy:

```powershell
./scripts/manage-osdfir-lab.ps1 deploy -Enable "plaso,yara" -Disable "strings"
```

### Keeping the chart version current

A weekly GitHub Action ([.github/workflows/check-chart-version.yml](.github/workflows/check-chart-version.yml))
checks the upstream `osdfir-infrastructure` chart and opens an auto-merging
PR when a new version is available. The PR edits `terraform/variables.tf`,
`README.md`, and appends a line under `## [Unreleased]` in
[CHANGELOG.md](CHANGELOG.md). You just pull `main` and redeploy.

Requires **"Allow auto-merge"** enabled in repo Settings -> General.

## Useful Resources

- **[Updating the Lab](docs/updating_osdfir_lab.md)** - How versions flow through the lab: what's automated, what's manual, and the full update/verification checklist.
- **[Official OSDFIR Documentation](https://osdfir.org/)**

## Troubleshooting Tips

- When re-deploying after a DFIQ flip, if the UI says "No question found with this ID", close and re-open the browser.
- Terraform may time out waiting for pods to start on slow machines. That does not mean the deploy failed — check `kubectl get pods -n osdfir` or `./scripts/manage-osdfir-lab.ps1 status`.
- If Timesketch's AI features warn that a provider is needed right after deploy, wait a minute for the Ollama init-container to finish the model pull, then reload the browser.
- First deployment downloads images + the Ollama model (several GB). The management script extends Helm's timeout automatically and prints periodic progress reminders.
- `./scripts/manage-osdfir-lab.ps1 logs` shows any problem pods without spamming healthy pod output; `logs -All` shows every pod.
- The Minikube tunnel job occasionally stops after OS sleep / Docker restart. `./scripts/manage-osdfir-lab.ps1 start` re-establishes it.
- For more serious testing, point Ollama at a larger model or an external LLM endpoint.

## Known Issues

- LLM responses on the default small model (`qwen2.5:0.5b`) can time out on longer prompts. Swap in a bigger model or an external provider for reliable results.

## To-Do List

### Project Improvements
- **Organization**: Refine project structure and code organization
- **Standardization**: Create consistent patterns across configuration files
- **Documentation**: Update docs and create comprehensive how-to guides
- **Deployment**: Improve deployment process and error handling
- **Pod Management**: Enhance methods to add/remove/modify pods
- **Integration**: Verify Yeti and HashR post-deploy credential sharing with Timesketch
- **External LLMs**: Determine settings for using LLMs outside of the pods
- **OpenSearch Management**: Establish process for backing up/upgrading/scaling OpenSearch

## Contributing

This is a personal lab project, though suggestions and improvements are welcome!

Otherwise, contribute to the upstream source projects:

- <https://github.com/google/osdfir-infrastructure>
- <https://github.com/google/timesketch>
- <https://github.com/openrelik>
- <https://github.com/timesketch/timesketch-mcp-server>
- <https://github.com/yeti-platform/yeti-mcp>

## Disclaimer

> **⚠️ Personal Test Lab Environment**  
> This is a personal development and testing lab for experimenting with OSDFIR tools and AI integration features. It's designed for learning, development, and fun - not for production use.

## Author

Kevin Stokes

[Blog](https://dfir-kev.medium.com/) · [LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/)

[Mmm Coffee..](https://www.buymeacoffee.com/dfirkev) · [When Bored](https://www.teepublic.com/user/kstrike)

