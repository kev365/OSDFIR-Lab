# OSDFIR Minikube

A project for deploying Open Source Digital Forensics and Incident Response (OSDFIR) tools in a Minikube environment.

## Overview

This repository contains the necessary configuration files, Helm charts, and scripts to deploy a complete OSDFIR infrastructure stack using Minikube and Kubernetes.

## Project Structure

```
osdfir-minikube/
├── helm/                    # Local copy of the OSDFIR Helm chart
├── manifests/              # Kubernetes manifest files (PVC, Namespace)
├── scripts/                # Deployment and utility scripts
├── docs/                   # Mermaid flowcharts and documentation
├── notes.md                # Project notes and documentation
└── README.md               # This file
```

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 backend enabled
- [Windows PowerShell](https://docs.microsoft.com/en-us/powershell/) with permissions to run scripts (`Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`)

## Quick Start Guide

Follow these steps to deploy the OSDFIR infrastructure to your local Minikube environment.

### 1. Start Minikube

Open a PowerShell terminal as **Administrator** and run the `start-minikube.ps1` script. This will start Minikube with the required resources and enable necessary addons.

```powershell
cd scripts
./start-minikube.ps1
```

### 2. Deploy the OSDFIR Stack

Once Minikube is running, deploy the OSDFIR stack by running the `deploy.ps1` script. This script will set up the required storage and install all the tools using the local Helm chart.

```powershell
./deploy.ps1
```

The deployment may take several minutes to complete. You can monitor the status of the pods by running:
```powershell
kubectl get pods -n osdfir --watch
```

### 3. Accessing the Tools

Once all pods are in a `Running` state, you can access the tools by forwarding their ports. See the `notes.md` file or the Helm chart's `NOTES.txt` for specific instructions.

## Helm Chart Configuration

All tool configurations are managed in the `helm/values.yaml` file. You can modify this file to change image versions, resource limits, or other settings before running the `deploy.ps1` script.

## Components

This deployment includes various OSDFIR tools and services:

- [ ] Log aggregation and analysis tools
- [ ] Digital forensics platforms
- [ ] Incident response tools
- [ ] Monitoring and alerting

## Contributing

Please see the notes.md file for development guidelines and project notes.

## License

[License information to be added] 