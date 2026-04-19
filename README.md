
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

```
osdfir-lab/
├── backups/                # Project backups created by the update script
├── configs/                # Custom configuration files (Timesketch, values, etc.)
├── helm-addons/            # Add-on Helm templates (Ollama, Timesketch LLM config)
├── scripts/                # Management and utility scripts
└── terraform/              # IaC: namespace, PVCs, Helm release, toggles
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

# Access services at:
# - Timesketch:         http://localhost:5000
# - OpenRelik:          http://localhost:8711
# - OpenRelik API:      http://localhost:8710
# - Yeti:               http://localhost:9000
# - OpenSearch Dashboards: via Timesketch at /opensearch
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

- `osdfir-infrastructure` Helm chart: **2.8.6**
- Timesketch image: **20260311** (nginx `1.25.5-alpine-slim`, OpenSearch `3` (rolling 3.x), Redis `7.4.2-alpine`, Postgres `17.5-alpine`)
- OpenSearch Dashboards: **3** (rolling 3.x, exposed at `/opensearch` via the Timesketch host)
- OpenRelik core services: **0.7.0** (workers pinned to analyzer-config `0.2.0`, plaso `0.5.0`, timesketch `0.3.0`, hayabusa `0.3.0`, extraction `0.6.0`)
- Prometheus (OpenRelik): **v3.10.0**
- Yeti: **2.5.0** (Redis `7.4.2-alpine`, ArangoDB `3.11.8`)
- HashR: **v1.8.2** (Postgres `17.2-alpine`)
- Ollama image: **latest** (pinned via `terraform/ollama.tf`)
- Ollama model: `qwen2.5:0.5b` (configurable via `terraform/variables.tf`)

OpenSearch images use the rolling `3` tag to auto-pick up the latest 3.x build on pod restart. They will not automatically move to 4.x. The `osdfir-infrastructure` chart version is bumped via a weekly GitHub Action (`.github/workflows/check-chart-version.yml`) that opens an auto-merging PR when an upstream chart update is available; that PR also appends an entry to [CHANGELOG.md](CHANGELOG.md).

## 🚧 Work in Progress

### AI Integration (Experimental)

- **Ollama Server** - Local AI model hosting (`smollm:latest`). **NOTE: This is intentionally small for this project, feel free to adjust.**
- **Timesketch LLM Features** - Natural Language to Query (NL2Q) + Event Summarization (Working!)
- **OpenRelik AI Workers** - AI-powered evidence analysis (In Progress)
- **Timesketch MCP Server** - Prebuilt via GitHub Actions, deployable via Terraform toggle.
- **Yeti MCP Server** - in consideration to add

**Current Status:** 
- Basic integration working, expanding AI capabilities across tools.
- The model will be slow and may time out. However the purpose was deploy with something of reasonable size that is functional.
- A larger model will be needed for better results and performance.

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
- When re-deploying, with the DFIQ previously enabled, if you get this message "No question found with this ID", try closing and re-opening the browser.
- Eventually, Terraform my timeout waiting on the pods to all start up, use command `kubectl get pods -n osdfir` to check status. Terraform timing out does not mean the deployment failed, simply that Terraform stopped waiting.
- After initial deployment, if the Timesketch AI features warn that a provider is needed, you may need to wait and reload the browser to see if the settings will work.
- On a first deployment the management script automatically extends Helm’s timeout and will periodically remind you that you can run `kubectl get deploy -n osdfir` in another terminal—expect a longer wait while images download and the Ollama model is pulled.
- For more serious testing, connect to a stronger LLM

## Known Issues / Troubleshooting Tips
- Still some issues coming up with partial re-deployments/installs, mostly with secrets.
- LLM features not fully functional in this lab, with the default deployment several features work, but may timeout.

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

Otherwise, contribute to source projects!
- https://github.com/google/osdfir-infrastructure
- https://github.com/google/timesketch
- https://github.com/openrelik
- https://github.com/timesketch/timesketch-mcp-server

## Disclaimer

> **⚠️ Personal Test Lab Environment**  
> This is a personal development and testing lab for experimenting with OSDFIR tools and AI integration features. It's designed for learning, development, and fun - not for production use.

## Author

Kevin Stokes

[Blog](https://dfir-kev.medium.com/) · [LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/)

[Mmm Coffee..](https://www.buymeacoffee.com/dfirkev) · [When Bored](https://www.teepublic.com/user/kstrike)

