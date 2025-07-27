
![Version](https://img.shields.io/badge/version-20240721-orange) · 
![GitHub release downloads](https://img.shields.io/github/downloads/kev365/OSDFIR-Lab/total)

![GitHub forks](https://img.shields.io/github/forks/kev365/OSDFIR-Lab?style=social) · 
![GitHub stars](https://img.shields.io/github/stars/kev365/OSDFIR-Lab?style=social) · 
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

# OSDFIR Lab

**Version:** 20240727

A test lab environment for deploying Open Source Digital Forensics and Incident Response (OSDFIR) tools in a Minikube environment with integrated AI capabilities using Docker Desktop.

- Source project: https://github.com/google/osdfir-infrastructure

## Overview

This repository provides a complete lab setup for OSDFIR tools running on Kubernetes via Minikube. It includes automated deployment scripts, AI integration experiments, and a unified management interface for easy testing and development.

## Project Structure

```
osdfir-lab/
├── backups/                # Project backups created by the update script
├── configs/                # Custom configuration files for deployments
├── helm/                   # OSDFIR Lab Helm chart with AI integration
├── scripts/                # Management and utility scripts
└── terraform/              # Infrastructure as Code (namespace, PVC, Helm release)
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
- RAM: 32GB+ system memory
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

```powershell
# Check status
./scripts/manage-osdfir-lab.ps1 status

# Get login credentials
./scripts/manage-osdfir-lab.ps1 creds

# Access services at:
# - Timesketch: http://localhost:5000
# - OpenRelik: http://localhost:8711
# - OpenRelik API: http://localhost:8710
```

### Cleanup

```powershell
./scripts/manage-osdfir-lab.ps1 teardown-lab
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
- **Helm** - Package management
- **Docker Desktop** - Container runtime

## 🚧 Work in Progress

### AI Integration (Experimental)

- **Ollama Server** - Local AI model hosting (`qwen2.5:0.5b`). **NOTE: This is intentionally small for this project, feel free to adjust.**
- **Timesketch LLM Features** - Natural Language to Query (NL2Q) + Event Summarization (Working!)
- **OpenRelik AI Workers** - AI-powered evidence analysis (In Progress)
- **Centralized AI Configuration** - Single YAML file for all AI settings
- **Timesketch MCP Server** - Provides programmatic interaction with Timesketch. (Deployed and connects to LLM, needs usage info.)
- **Yeti MCP Server** - in consideration to add

**Current Status:** 
- Basic integration working, expanding AI capabilities across tools.
- The model will be slow and may time out. However the purpose was deploy with something of reasonable size that is functional.
- A larger model will be needed for best results and performance.

## Management

The unified management script handles all operations:

```powershell
./scripts/manage-osdfir-lab.ps1 [action]

# Key actions:
deploy          # Full deployment
status          # Check everything
start/stop      # Service access
creds           # Login credentials
ollama          # AI model status
teardown-lab    # Complete cleanup
```

For manual control or troubleshooting, see [commands.md](commands.md).

## Useful Resources

- **[Updating the Lab](updating_osdfir_lab.md)** - Instructions for updating the lab components.
- **[Official OSDFIR Documentation](https://osdfir.org/)**

## Known Issues
- Still some issues coming up with partial re-deployments/installs, mostly with secrets. Currently full teardown and deploy works, just slower.
- When re-deploying, with the DFIQ previously enabled, if you get this message "No question found with this ID", try closing and re-opening the browser.
- LLM features not fully functional in this lab.

## Contributing

This is a personal lab project, though suggestions and improvements are welcome! 

Otherwise, contribute to source projects!
- https://github.com/google/osdfir-infrastructure
- https://github.com/google/timesketch
- https://github.com/openrelik


## Disclaimer

> **⚠️ Personal Test Lab Environment**  
> This is a personal development and testing lab for experimenting with OSDFIR tools and AI integration features. It's designed for learning, development, and fun - not for production use.

## Author

Kevin Stokes

[Blog](https://dfir-kev.medium.com/) · [LinkedIn Profile](https://www.linkedin.com/in/dfir-kev/)

[Mmm Coffee..](https://www.buymeacoffee.com/dfirkev) · [When Bored](https://www.teepublic.com/user/kstrike)

