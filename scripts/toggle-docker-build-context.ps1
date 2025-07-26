<#
.SYNOPSIS
Toggles Docker CLI context between Minikube and Docker Desktop.

.DESCRIPTION
This script checks the current Docker environment configuration and toggles between:
- Docker Desktop (the default local Docker engine), and
- Minikube's Docker daemon (for building images directly inside a Minikube cluster, e.g., "osdfir").

When switching to Minikube, it sets the required environment variables using `minikube docker-env`.
When switching back to Docker Desktop, it unsets those environment variables.

Helpful build and deployment tips are displayed when switching into Minikube mode.

.NOTES
- This script is designed for PowerShell on Windows.
- It assumes a Minikube profile named "osdfir" is already created and running.
- Requires Docker and Minikube to be installed and accessible in the current shell.

.AUTHOR
kev365

.LASTEDIT
2025-07-26

.EXAMPLE
.\toggle-docker-build-context.ps1

This will switch from Docker Desktop to Minikube or vice versa, depending on the current state.
#>

function Write-Info($message) {
    Write-Host $message -ForegroundColor Cyan
}
function Write-WarningMessage($message) {
    Write-Host $message -ForegroundColor Yellow
}
function Write-ErrorMessage($message) {
    Write-Host $message -ForegroundColor Red
}
function Write-Success($message) {
    Write-Host $message -ForegroundColor Green
}
function Write-Tip($message) {
    Write-Host $message -ForegroundColor DarkGray
}

# Check if Docker is running
$info = docker info 2>$null
if (-not $info) {
    Write-ErrorMessage "Docker is not running or not available. Please check Docker Desktop or Minikube."
    exit 1
}

# Determine whether we’re in Minikube or Desktop based on DOCKER_HOST
$currentHost = $Env:DOCKER_HOST

if ($currentHost -and $currentHost.StartsWith("tcp://")) {
    # Currently using Minikube
    Write-WarningMessage "Switching Docker context to Docker Desktop..."

    # Properly unset Minikube's Docker env vars
    Remove-Item Env:DOCKER_TLS_VERIFY -ErrorAction SilentlyContinue
    Remove-Item Env:DOCKER_HOST -ErrorAction SilentlyContinue
    Remove-Item Env:DOCKER_CERT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:MINIKUBE_ACTIVE_DOCKERD -ErrorAction SilentlyContinue

    Write-Success "Now using Docker Desktop engine for image building."
}
else {
    # Currently using Docker Desktop
    Write-WarningMessage "Switching Docker context to Minikube..."

    # Set Docker env to Minikube
    minikube -p osdfir docker-env --shell powershell | Invoke-Expression

    Write-Success "Now using Minikube's Docker daemon for image building."
    Write-Info "Reminder: Run this script again to switch back to Docker Desktop after building."

    Write-Host ""
    Write-Info "Build & Deploy Tips:"
    Write-Tip "  docker build -t my-custom-image:latest ."
    Write-Tip "  kubectl set image deployment/<deployment-name> <container-name>=my-custom-image:latest"
    Write-Tip "  helm upgrade --install <release-name> ./chart-path --set image.tag=latest"
    Write-Tip "  kubectl rollout restart deployment <deployment-name>"
    Write-Host ""
}
