# OSDFIR Minikube Management Script
# Unified tool for managing OSDFIR deployment, services, and credentials on Minikube

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("help", "status", "start", "stop", "restart", "logs", "cleanup", "creds", "jobs", "helm", "uninstall", "storage", "minikube", "deploy", "undeploy")]
    [string]$Action = "help",
    
    [Parameter(Mandatory = $false)]
    [string]$ReleaseName = "osdfir-lab",
    
    [Parameter(Mandatory = $false)]
    [string]$Namespace = "osdfir",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("all", "timesketch", "openrelik")]
    [string]$Service = "all",
    
    # Help alias
    [switch]$h = $false,
    
    # Cleanup and deployment options
    [switch]$Force = $false,
    [switch]$DryRun = $false
)

# ... existing code ...
