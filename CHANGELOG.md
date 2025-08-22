# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to a `YYYYMMDD` versioning scheme.

## [20250822] - 2025-08-22

### Added
- GitHub workflow for building and publishing Timesketch MCP Server Docker image
- Helm chart structure for custom add-ons (helm-addons directory)
- Terraform variable to control Ollama deployment (deploy_ollama)
- Terraform variable to control MCP Server deployment (deploy_mcp_server)
- Enhanced Timesketch LLM integration with Ollama

### Changed
- Refactored deployment to use upstream osdfir-infrastructure Helm chart
- Improved Minikube management in deployment scripts
- Optimized tarball creation for Timesketch configuration, with GitHub workflow creation
- Updated Terraform configuration to use Kubernetes provider properly
- Address some issues

### Removed
- Local copies of Helm, Timesketch, and DFIQ data files (now pulled from upstream)

## [20250721] - 2025-07-21

### Added
- Initial setup of the OSDFIR Lab environment.
- Deployment scripts for Minikube using Terraform and Helm.
- Integration of Timesketch and OpenRelik.
- Experimental AI integration with an Ollama server.
- Project `README.md` with setup instructions.
- Initial `CHANGELOG.md` to track project evolution.
- `usage_examples.md` to guide new users.