# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to a `YYYYMMDD` versioning scheme.

## [20260319] - 2026-03-19

### Changed
- Bumped Timesketch to image tag **20260311** (from 20251114) — adds Plaso event filters, starred-events-to-forensic-report LLM feature.
- Bumped OpenRelik core components (UI, server, mediator, metrics) to **0.7.0** (from 0.6.0) — adds ADK integration, workflow engine, SSE streaming.
- Bumped `openrelik-worker-plaso` to **0.5.0** (from 0.4.0) and `openrelik-worker-extraction` to **0.6.0** (from 0.5.0).
- Bumped Prometheus to **v3.10.0** (from v3.0.1).
- Added "Changing the LLM model" quick-reference to `docs/updating_osdfir_lab.md`.
- Updated version baseline documentation in `README.md` and `docs/updating_osdfir_lab.md`; updated project version badge to **20260319**.

## [20260318] - 2026-03-18

### Added
- Enabled **HashR** (`v1.8.2`) for hash verification and analysis.
- Enabled **Yeti** (`2.5.0`) threat intelligence platform with ArangoDB `3.11.8` and Redis `7.4.2-alpine`.
- Yeti port forwarding (`http://localhost:9000`) and credential retrieval in `manage-osdfir-lab.ps1`.
- Configured Timesketch integration with HashR (database address) and Yeti (API endpoint).

### Changed
- Upgraded to `osdfir-infrastructure` Helm chart **2.8.4** (from 2.5.6).
- Updated Yeti images to `2.5.0`, ArangoDB to `3.11.8`, Redis to `7.4.2-alpine`.
- Updated HashR PostgreSQL to `17.2-alpine`.
- Updated version baseline documentation in `README.md` and `docs/updating_osdfir_lab.md`; updated project version badge to **20260318**.
- Fixed `Hshr` typo in `osdfir-lab-values.yaml` comment.

## [20251120] - 2025-11-21

### Added
- First-deployment detection and extended Terraform/Helm timeout handling in `scripts/manage-osdfir-lab.ps1`, including periodic status reminders during long rollouts.

### Changed
- Upgraded to `osdfir-infrastructure` Helm chart **2.5.6**.
- Bumped Timesketch to image tag **20251114** with aligned dependency images (nginx `1.25.5-alpine-slim`, OpenSearch `3.1.0`, Redis `7.4.2-alpine`, Postgres `17.5-alpine`).
- Bumped OpenRelik components to **0.6.0** and pinned worker images (analyzer-config `0.2.0`, plaso `0.4.0`, timesketch `0.3.0`, hayabusa `0.3.0`, extraction `0.5.0`).
- Swapped the default Ollama model to `smollm:latest` and hardened the model pull init script for Windows-safe execution.
- Documented the new component versions and deployment guidance in `README.md` and `docs/updating_osdfir_lab.md`; updated project version badge to **20251120**.

### Fixed
- Resolved CRLF-related failures in the Ollama init container by normalising scripts before execution.

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