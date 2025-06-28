#Requires -RunAsAdministrator

# start-minikube.ps1
# This script starts Minikube with recommended settings for the OSDFIR stack.
# It requires administrative privileges to run.

# Configuration
$Memory = "8192"  # 8GB
$CPUs = "4"
$Driver = "docker" # Using docker driver for WSL2

# Check if Minikube is already running
$minikubeStatus = minikube status -f "{{.Host}}"
if ($minikubeStatus -eq "Running") {
    Write-Host "Minikube is already running."
}
else {
    Write-Host "Starting Minikube with $Memory MB of memory, $CPUs CPUs, and the '$Driver' driver..."
    minikube start --driver=$Driver --memory=$Memory --cpus=$CPUs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Minikube failed to start. Please check your Docker Desktop and WSL2 setup."
        exit 1
    }
    Write-Host "Minikube started successfully."
}

# Enable required addons
Write-Host "Enabling Minikube addons..."
minikube addons enable ingress
minikube addons enable storage-provisioner

Write-Host "Minikube setup is complete." 