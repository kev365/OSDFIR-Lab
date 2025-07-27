<#
.SYNOPSIS
Build script for Timesketch MCP Server Docker image with automatic deployment integration.

.DESCRIPTION
This script builds the Timesketch MCP Server Docker image and optionally integrates with 
OSDFIR Lab deployment workflows. It provides advanced features including:

- Automatic Docker context switching between Docker Desktop and Minikube
- Minikube lifecycle management (start/stop as needed)
- Existing deployment detection and automatic updates
- Context restoration and error handling
- Integration with OSDFIR Lab management scripts

.PARAMETER Minikube
Switch to Minikube context for building. Automatically manages Minikube lifecycle.

.PARAMETER Force
Run without confirmation prompts.

.PARAMETER h
Show help information.

.PARAMETER Help
Show help information.

.NOTES
- This script is designed for PowerShell on Windows.
- It assumes the timesketch-mcp-server source is in the mcp/timesketch-mcp-server directory.
- Requires Docker to be installed and accessible in the current shell.
- For Minikube builds: requires Minikube and kubectl to be installed.
- For deployment integration: requires kubectl access to the osdfir namespace.

.AUTHOR
kev365

.LASTEDIT
2025-01-27

.EXAMPLE
.\build-timesketch-mcp.ps1

This will build the timesketch-mcp-server image using Docker Desktop context.

.EXAMPLE
.\build-timesketch-mcp.ps1 -Minikube

This will switch to Minikube context, build the image there, and automatically update 
existing deployments if found.

.EXAMPLE
.\build-timesketch-mcp.ps1 -Force

This will build without confirmation prompts.

.EXAMPLE
.\build-timesketch-mcp.ps1 -h

This will show detailed help information.
#>

param(
    [switch]$Minikube = $false,
    [switch]$Force = $false,
    [switch]$h = $false,
    [switch]$Help = $false,
    [switch]$CalledByManager = $false
)

# Color constants for output
$Colors = @{
    Header = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "White"
    Gray = "Gray"
}

# Helper functions for colored output
function Write-Info { param([string]$Message) Write-Host $Message -ForegroundColor $Colors.Info }
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor $Colors.Success }
function Write-WarningMessage { param([string]$Message) Write-Host $Message -ForegroundColor $Colors.Warning }
function Write-ErrorMessage { param([string]$Message) Write-Host $Message -ForegroundColor $Colors.Error }

# Show help if -h or -Help is invoked
if ($h -or $Help) {
    Write-Host "== Timesketch MCP Server Build Tool ==" -ForegroundColor $Colors.Header
    Write-Host "=====================================" -ForegroundColor $Colors.Header
    Write-Host ""
    Write-Host "Usage: .\build-timesketch-mcp.ps1 [options]" -ForegroundColor $Colors.Warning
    Write-Host ""
    Write-Host "This script builds the Timesketch MCP Server Docker image with advanced" -ForegroundColor $Colors.Info
    Write-Host "deployment integration features." -ForegroundColor $Colors.Info
    Write-Host ""
    Write-Host "Options:" -ForegroundColor $Colors.Success
    Write-Host "  -h         Show help (alias: -Help)" -ForegroundColor $Colors.Info
    Write-Host "  -Force     Run without confirmation prompts" -ForegroundColor $Colors.Info
    Write-Host "  -Minikube  Build in Minikube context (switches Docker context)" -ForegroundColor $Colors.Info
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor $Colors.Success
    Write-Host "  .\build-timesketch-mcp.ps1" -ForegroundColor $Colors.Info
    Write-Host "  .\build-timesketch-mcp.ps1 -Minikube" -ForegroundColor $Colors.Info
    Write-Host "  .\build-timesketch-mcp.ps1 -Force" -ForegroundColor $Colors.Info
    Write-Host ""
    Write-Host "Features:" -ForegroundColor $Colors.Success
    Write-Host "  - Automatic Docker context switching" -ForegroundColor $Colors.Info
    Write-Host "  - Minikube lifecycle management" -ForegroundColor $Colors.Info
    Write-Host "  - Existing deployment detection and updates" -ForegroundColor $Colors.Info
    Write-Host "  - Context restoration and error handling" -ForegroundColor $Colors.Info
    Write-Host "  - Integration with OSDFIR Lab workflows" -ForegroundColor $Colors.Info
    return
}

# Function to restore Docker Desktop context
function Restore-DockerDesktopContext {
    Write-Info "Restoring Docker Desktop context..."
    Remove-Item Env:DOCKER_TLS_VERIFY -ErrorAction SilentlyContinue
    Remove-Item Env:DOCKER_HOST -ErrorAction SilentlyContinue
    Remove-Item Env:DOCKER_CERT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:MINIKUBE_ACTIVE_DOCKERD -ErrorAction SilentlyContinue
    Write-Success "Restored Docker Desktop context."
}

# Function to check if currently in Minikube context
function Test-MinikubeContext {
    return $Env:DOCKER_HOST -and $Env:DOCKER_HOST.StartsWith("tcp://")
}

# Function to check if Minikube is running
function Test-MinikubeRunning {
    try {
        $status = minikube -p osdfir status 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $status -and $status.Contains("Running")
        }
        return $false
    } catch {
        return $false
    }
}

# Function to check if deployment exists
function Test-DeploymentExists {
    $deployment = kubectl get deployment osdfir-lab-timesketch-mcp-server -n osdfir --ignore-not-found 2>$null
    return $deployment -and $deployment.Length -gt 0
}

# Main script logic
Write-Host ""
Write-Host "== Timesketch MCP Server Build Tool ==" -ForegroundColor $Colors.Header
Write-Host "=====================================" -ForegroundColor $Colors.Header
Write-Host ""

# Check if we're in the correct directory
$projectRoot = Split-Path -Parent $PSScriptRoot
$mcpServerPath = Join-Path $projectRoot "configs\timesketch-mcp-server"

if (-not (Test-Path $mcpServerPath)) {
    Write-ErrorMessage "ERROR: Timesketch MCP Server directory not found at: $mcpServerPath"
    Write-Info "Please ensure you're running this script from the OSDFIR Lab project root."
    exit 1
}

# Check if Docker is available
try {
    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage "ERROR: Docker is not running or not available"
        Write-Info "Please start Docker Desktop and try again."
        exit 1
    }
} catch {
    Write-ErrorMessage "ERROR: Docker command not found"
    Write-Info "Please install Docker Desktop and try again."
    exit 1
}

# Handle Minikube context switching
$originalDockerHost = $Env:DOCKER_HOST

if ($Minikube) {
    # If not called by the manager, perform lifecycle checks
    if (-not $CalledByManager) {
        $minikubeWasRunning = Test-MinikubeRunning
        $minikubeStartedByScript = $false
        
        if (-not $minikubeWasRunning) {
            Write-WarningMessage "Minikube is not running. Starting Minikube with osdfir profile..."
            minikube -p osdfir start
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorMessage "Failed to start Minikube. Please check your Minikube installation."
                exit 1
            }
            Write-Success "Minikube started successfully."
            $minikubeStartedByScript = $true
        } else {
            Write-Info "Minikube is already running."
        }
    }
    
    if (Test-MinikubeContext) {
        Write-Info "Already in Minikube context. Proceeding with build..."
    } else {
        Write-WarningMessage "Switching Docker context to Minikube for building..."
        try {
            $minikubeOutput = minikube -p osdfir docker-env --shell powershell
            if ($LASTEXITCODE -eq 0) {
                $minikubeOutput | Invoke-Expression
                Write-Success "Now using Minikube's Docker daemon for building."
            } else {
                Write-ErrorMessage "Failed to get Minikube Docker environment. Exit code: $LASTEXITCODE"
                exit 1
            }
        } catch {
            Write-ErrorMessage "Error setting Minikube Docker environment: $($_.Exception.Message)"
            exit 1
        }
    }
    Write-Info "Context will be automatically restored after build."
}

# Confirmation prompt (unless -Force is used)
if (-not $Force) {
    Write-Host ""
    $confirmation = Read-Host "Build Timesketch MCP Server Docker image? (y/N)"
    if ($confirmation -ne "y" -and $confirmation -ne "Y") {
        Write-Info "Build cancelled."
        exit 0
    }
}

# Navigate to project root and build
Push-Location $projectRoot
try {
    Write-Host ""
    Write-Host "Building Timesketch MCP Server Docker image..." -ForegroundColor $Colors.Info
    Write-Host "Build context: $projectRoot" -ForegroundColor $Colors.Gray
    Write-Host "Dockerfile: configs/timesketch-mcp-server/docker/Dockerfile" -ForegroundColor $Colors.Gray
    Write-Host ""
    
    # Navigate to the MCP server directory for the build
    Push-Location $mcpServerPath
    try {
        Write-Host "Changed to MCP server directory: $(Get-Location)" -ForegroundColor $Colors.Gray
        Write-Host ""
        
        # Build the Docker image from the MCP server directory
        docker build -t timesketch-mcp-server:latest -f docker/Dockerfile .
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Docker image built successfully!"
            
            # Check for existing deployment and update if found
            if ($Minikube -and (Test-DeploymentExists)) {
                Write-Host ""
                Write-Info "Existing deployment found. Updating deployment..."
                
                # Update the deployment with the new image
                kubectl set image deployment/timesketch-mcp-server timesketch-mcp-server=timesketch-mcp-server:latest -n osdfir
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Deployment image updated successfully!"
                    
                    # Restart the deployment
                    Write-Info "Restarting deployment..."
                    kubectl rollout restart deployment/timesketch-mcp-server -n osdfir
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Deployment restarted successfully!"
                        Write-Host ""
                        Write-Info "Next steps:"
                        Write-Info "  - Monitor deployment: kubectl get pods -n osdfir -w"
                        Write-Info "  - Check logs: kubectl logs -f deployment/timesketch-mcp-server -n osdfir"
                    } else {
                        Write-WarningMessage "Failed to restart deployment. You may need to restart manually."
                    }
                } else {
                    Write-WarningMessage "Failed to update deployment image. You may need to update manually."
                }
            } else {
                Write-Host ""
                Write-Info "Next steps:"
                Write-Info "  - Deploy to OSDFIR Lab: .\scripts\manage-osdfir-lab.ps1 deploy"
            }
        } else {
            Write-ErrorMessage "Docker build failed!"
            exit 1
        }
    } finally {
        Pop-Location  # Return to project root
    }
} finally {
    Pop-Location  # Return to original directory
    if ($Minikube) {
        if ($null -eq $originalDockerHost -or -not $originalDockerHost.StartsWith("tcp://")) {
            Restore-DockerDesktopContext
        } else {
            Write-Info "Already in Minikube context. No restoration needed."
        }
        # If not called by the manager, check if we need to stop Minikube
        if (-not $CalledByManager) {
            if ($minikubeStartedByScript) {
                Write-Info "Stopping Minikube..."
                minikube -p osdfir stop
                Write-Success "Minikube stopped."
            }
        }
    }
}

Write-Host ""
Write-Success "Build process completed!"