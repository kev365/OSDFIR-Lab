# OSDFIR Lab

A test lab environment for deploying Open Source Digital Forensics and Incident Response (OSDFIR) tools in a Minikube environment with integrated AI capabilities using Docker Desktop.

- Source project: https://github.com/google/osdfir-infrastructure

## Overview

This repository provides a complete lab setup for OSDFIR tools running on Kubernetes via Minikube. It includes automated deployment scripts, AI integration experiments, and a unified management interface for easy testing and development.

## Project Structure

```
osdfir-minikube/
├── helm/                    # OSDFIR Lab Helm chart with AI integration
├── terraform/              # Infrastructure as Code (namespace, PVC, Helm release)
├── scripts/                # Management and utility scripts
├── docs/                   # Mermaid flowcharts and documentation
├── unused/                 # Archived files for reference
├── commands.md             # Useful command reference
├── notes.md                # Project notes and documentation
└── README.md               # This file
```

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 backend enabled
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
- Windows 11 Pro with WSL2 enabled
- Docker Desktop for Windows
  - Memory allocation: 8GB+ (configured in Docker Desktop settings)
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
./scripts/manage-osdfir-lab.ps1 teardown-lab -Force
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

- **Ollama Server** - Local AI model hosting (`gemma2:2b`)
- **Timesketch LLM Features** - Natural Language to Query (NL2Q) + Event Summarization
- **OpenRelik AI Workers** - AI-powered evidence analysis
- **Centralized AI Configuration** - Single YAML file for all AI settings

**Current Status:** Basic integration working, expanding AI capabilities across tools.

### Future Enhancements

- [ ] Additional AI models and providers
- [ ] Advanced workflow automation
- [ ] Cross-tool AI integration
- [ ] Performance optimization
- [ ] Enhanced documentation and tutorials

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

## Advanced Configuration

### AI Model Settings

Edit `helm/osdfir-lab-values.yaml`:

```yaml
ai:
  model:
    name: "gemma2:2b"                    # Change model here
    provider: "ollama"
    temperature: 0.1                     # Creativity level
    max_input_tokens: 4096
```

Then update: `helm upgrade osdfir-lab ./helm --namespace osdfir --values helm/osdfir-lab-values.yaml`

## Useful Resources

- **[Commands Reference](commands.md)** - Comprehensive command list
- **[Deployment Workflow](docs/workflow.mmd)** - Visual deployment and usage flowchart
- **[Project Notes](notes.md)** - Development guidelines and notes
- **[Official OSDFIR Documentation](https://osdfir.org/)**

## Contributing

This is a personal lab project, though suggestions and improvements are welcome! 

Otherwise, contribute to source projects!
- https://github.com/google/osdfir-infrastructure
- https://github.com/google/timesketch
- https://github.com/openrelik


## Disclaimer

> **⚠️ Personal Test Lab Environment**  
> This is a personal development and testing lab for experimenting with OSDFIR tools and AI integration. It's designed for learning, development, and fun - not for production use.

## License

Apache License Version 2.0
