# OSDFIR Lab Management Script
# Unified tool for managing OSDFIR deployment, services, and credentials on Minikube

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("help", "status", "start", "stop", "restart", "logs", "cleanup", "creds", "jobs", "helm", "uninstall", "reinstall", "storage", "minikube", "deploy", "teardown-lab", "teardown-lab-all", "ollama", "ollama-test", "docker")]
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

# Color constants
$Colors = @{
    Header = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "White"
    Gray = "Gray"
}

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "== $Title ==" -ForegroundColor $Colors.Header
    Write-Host ("=" * ($Title.Length + 7)) -ForegroundColor $Colors.Header
}

function Show-Help {
    Show-Header "OSDFIR Lab Management Tool"
    Write-Host ""
    Write-Host "Usage: .\manage-osdfir-lab.ps1 [action] [options]" -ForegroundColor $Colors.Warning
    Write-Host ""
    Write-Host "DEPLOYMENT + TEARDOWN:" -ForegroundColor $Colors.Success
    Write-Host "  deploy           - Full deployment (Docker + Minikube + Terraform + Services)"
    Write-Host "  teardown-lab     - Smart cleanup (Services + Terraform, PRESERVES AI models/data)" -ForegroundColor $Colors.Header
    Write-Host "  teardown-lab-all - Complete destruction (Everything including AI models/data)" -ForegroundColor $Colors.Error
    Write-Host "  docker           - Check and start Docker Desktop if needed"
    Write-Host ""
    Write-Host "STATUS + MONITORING:" -ForegroundColor $Colors.Success
    Write-Host "  status       - Show deployment and service status"
    Write-Host "  minikube     - Show Minikube cluster status"
    Write-Host "  helm         - List Helm releases and show release status"
    Write-Host "  storage      - Show PV storage utilization"
    Write-Host "  jobs         - Manage background jobs"
    Write-Host "  logs         - Show logs from services"
    Write-Host ""
    Write-Host "SERVICE ACCESS:" -ForegroundColor $Colors.Success
    Write-Host "  start        - Start port forwarding for services"
    Write-Host "  stop         - Stop port forwarding jobs"
    Write-Host "  restart      - Restart port forwarding jobs"
    Write-Host "  creds        - Get service credentials"
    Write-Host ""
    Write-Host "AI + SPECIALIZED:" -ForegroundColor $Colors.Success
    Write-Host "  ollama       - Show Ollama AI model status and connectivity"
    Write-Host "  ollama-test  - Run comprehensive AI prompt testing"
    Write-Host ""
    Write-Host "MAINTENANCE:" -ForegroundColor $Colors.Success
    Write-Host "  cleanup      - Clean up OSDFIR deployment"
    Write-Host "  uninstall    - Uninstall the Helm release"
    Write-Host "  reinstall    - Reinstall the Helm release (uninstall + deploy)"
    Write-Host "  help         - Show this help message"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor $Colors.Header
    Write-Host "  -h                Show help (alias for help action)"
    Write-Host "  -Service          Specific service for creds (all, timesketch, openrelik)"
    Write-Host "  -Force            Force operations without confirmation"
    Write-Host "  -DryRun           Show what would be done without executing"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor $Colors.Header
    Write-Host "  .\manage-osdfir-lab.ps1 -h"
    Write-Host "  .\manage-osdfir-lab.ps1 docker"
    Write-Host "  .\manage-osdfir-lab.ps1 deploy            # Preserves passwords if they exist"
    Write-Host "  .\manage-osdfir-lab.ps1 reinstall         # Reinstall while preserving passwords"
    Write-Host "  .\manage-osdfir-lab.ps1 teardown-lab      # Smart cleanup - preserves AI models/data" -ForegroundColor $Colors.Header
    Write-Host "  .\manage-osdfir-lab.ps1 teardown-lab-all  # Nuclear option - destroys everything" -ForegroundColor $Colors.Error
    Write-Host "  .\manage-osdfir-lab.ps1 status"
    Write-Host "  .\manage-osdfir-lab.ps1 creds -Service timesketch"
}

function Test-Prerequisites {
    $missing = @()
    
    # Check required tools using Get-Command which is more reliable
    $tools = @("minikube", "kubectl", "terraform", "helm", "docker")
    foreach ($tool in $tools) {
        try {
            $command = Get-Command $tool -ErrorAction Stop
            Write-Verbose "Found $tool at: $($command.Source)" -Verbose:$false
        } catch {
            $missing += $tool
        }
    }
    
    if ($missing.Count -gt 0) {
        Write-Host "ERROR: Missing required tools: $($missing -join ', ')" -ForegroundColor $Colors.Error
        Write-Host "Please install all required tools before proceeding." -ForegroundColor $Colors.Warning
        Write-Host ""
        Write-Host "Installation tips:" -ForegroundColor $Colors.Info
        foreach ($tool in $missing) {
            switch ($tool) {
                "kubectl" { Write-Host "  - kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/" -ForegroundColor $Colors.Gray }
                "docker" { Write-Host "  - docker: https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor $Colors.Gray }
                "minikube" { Write-Host "  - minikube: https://minikube.sigs.k8s.io/docs/start/" -ForegroundColor $Colors.Gray }
                "terraform" { Write-Host "  - terraform: https://developer.hashicorp.com/terraform/downloads" -ForegroundColor $Colors.Gray }
                "helm" { Write-Host "  - helm: https://helm.sh/docs/intro/install/" -ForegroundColor $Colors.Gray }
            }
        }
        return $false
    }
    
    return $true
}

function Get-OptimalResources {
    # Get system memory in GB
    $totalMemoryGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    
    # Get Docker Desktop's available memory
    $dockerMemoryMB = 0
    try {
        $dockerInfo = docker system info --format "{{.MemTotal}}" 2>$null
        if ($dockerInfo) {
            $dockerMemoryMB = [math]::Round($dockerInfo / 1MB, 0)
        }
    } catch {
        Write-Host "Warning: Could not determine Docker memory limit" -ForegroundColor $Colors.Warning
    }
    
    # Calculate memory allocation
    if ($dockerMemoryMB -gt 0) {
        # Use 80% of Docker's available memory, minimum 4GB for AI workloads
        $dockerMemoryGB = [math]::Round($dockerMemoryMB / 1024, 1)
        $memoryGB = [math]::Max([math]::Floor($dockerMemoryGB * 0.8), 4)
        
        # Ensure we don't exceed Docker's limits
        if ($memoryGB -gt ($dockerMemoryGB - 2)) {
            $memoryGB = [math]::Max($dockerMemoryGB - 2, 4)
        }
    } else {
        # Fallback to system memory calculation
        $memoryGB = [math]::Max([math]::Floor($totalMemoryGB * 0.5), 4)
    }
    
    # Get CPU count and use half, minimum 2, maximum 8 for balanced performance
    $totalCPUs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    $cpus = [math]::Min([math]::Max([math]::Floor($totalCPUs / 2), 2), 8)
    
    Write-Host "System Resources:" -ForegroundColor $Colors.Success
    Write-Host "  Total Memory: ${totalMemoryGB}GB"
    Write-Host "  Total CPUs: $totalCPUs"
    if ($dockerMemoryMB -gt 0) {
        Write-Host "  Docker Memory: ${dockerMemoryGB}GB" -ForegroundColor $Colors.Success
    }
    Write-Host ""
    Write-Host "Minikube Allocation:" -ForegroundColor $Colors.Warning
    Write-Host "  Memory: ${memoryGB}GB"
    Write-Host "  CPUs: $cpus"
    Write-Host ""
    
    return @{
        Memory = "${memoryGB}GB"
        CPUs = $cpus
    }
}

function Test-Docker {
    param([switch]$Silent = $false)
    
    try {
        docker info > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            if (-not $Silent) {
                Write-Host "[OK] Docker is running" -ForegroundColor $Colors.Success
            }
            return $true
        } else {
            if (-not $Silent) {
                Write-Host "[ERROR] Docker is not running" -ForegroundColor $Colors.Error
            }
            return $false
        }
    } catch {
        if (-not $Silent) {
            Write-Host "[ERROR] Docker command not found" -ForegroundColor $Colors.Error
            Write-Host "Please install Docker Desktop and try again." -ForegroundColor $Colors.Warning
        }
        return $false
    }
}

function Set-ProxyEnvironment {
    # Check if proxy environment variables are set
    $proxyVars = @()
    
    if ($env:HTTP_PROXY) {
        $proxyVars += "--docker-env", "HTTP_PROXY=$env:HTTP_PROXY"
        Write-Host "Using HTTP_PROXY: $env:HTTP_PROXY" -ForegroundColor $Colors.Warning
    }
    
    if ($env:HTTPS_PROXY) {
        $proxyVars += "--docker-env", "HTTPS_PROXY=$env:HTTPS_PROXY"
        Write-Host "Using HTTPS_PROXY: $env:HTTPS_PROXY" -ForegroundColor $Colors.Warning
    }
    
    # Set NO_PROXY with Kubernetes and registry defaults
    $defaultNoProxy = "localhost,127.0.0.1,10.96.0.0/12,192.168.59.0/24,192.168.49.0/24,192.168.39.0/24,registry.k8s.io"
    
    if ($env:NO_PROXY) {
        $noProxy = "$env:NO_PROXY,$defaultNoProxy"
    } else {
        $noProxy = $defaultNoProxy
    }
    
    $proxyVars += "--docker-env", "NO_PROXY=$noProxy"
    Write-Host "Using NO_PROXY: $noProxy" -ForegroundColor $Colors.Warning
    
    return $proxyVars
}

function Start-MinikubeCluster {
    Write-Host ""
    Write-Host "Starting OSDFIR Minikube Cluster..." -ForegroundColor $Colors.Header
    Write-Host "=================================" -ForegroundColor $Colors.Header
    Write-Host ""
    
    # Check Docker
    if (-not (Test-Docker -Silent)) {
        Write-Host "[ERROR] Docker is not running" -ForegroundColor $Colors.Error
        return $false
    }
    
    # Get optimal resources
    $resources = Get-OptimalResources
    
    # Set proxy environment if needed
    $proxyArgs = Set-ProxyEnvironment
    
    Write-Host "Starting Minikube with profile 'osdfir'..." -ForegroundColor $Colors.Success
    
    # Build the minikube start command
    $minikubeArgs = @(
        "start",
        "--profile=osdfir",
        "--driver=docker",
        "--memory=$($resources.Memory)",
        "--cpus=$($resources.CPUs)",
        "--disk-size=40GB",
        "--kubernetes-version=stable"
    )
    
    # Add proxy arguments if any
    $minikubeArgs += $proxyArgs
    
    # Start Minikube
    try {
        $allArgs = $minikubeArgs + $proxyArgs
        $argumentList = $allArgs -join " "
        
        Write-Host "Running: minikube $argumentList" -ForegroundColor $Colors.Gray
        
        $process = Start-Process -FilePath "minikube" -ArgumentList $allArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -ne 0) {
            Write-Host "Failed to start Minikube!" -ForegroundColor $Colors.Error
            return $false
        }
        
        Write-Host ""
        Write-Host "[OK] Minikube started successfully" -ForegroundColor $Colors.Success
        
        # Enable required addons
        Write-Host ""
        Write-Host "Enabling Minikube addons..." -ForegroundColor $Colors.Success
        minikube addons enable ingress --profile=osdfir
        minikube addons enable storage-provisioner --profile=osdfir
        minikube addons enable default-storageclass --profile=osdfir
        
        # Set kubectl context
        Write-Host ""
        Write-Host "Setting kubectl context..." -ForegroundColor $Colors.Success
        kubectl config use-context osdfir
        
        Write-Host ""
        Write-Host "[OK] Minikube cluster is ready!" -ForegroundColor $Colors.Success
        Write-Host "Cluster IP: $(minikube ip --profile=osdfir)" -ForegroundColor $Colors.Warning
        
        return $true
        
    } catch {
        Write-Host "Error starting Minikube: $($_.Exception.Message)" -ForegroundColor $Colors.Error
        return $false
    }
}

function Start-MinikubeTunnel {
    Write-Host ""
    Write-Host "Starting Minikube tunnel..." -ForegroundColor $Colors.Success
    
    # Check if tunnel job already exists
    $existingJob = Get-Job -Name "minikube-tunnel" -ErrorAction SilentlyContinue
    if ($existingJob) {
        Write-Host "Stopping existing tunnel job..." -ForegroundColor $Colors.Warning
        $existingJob | Stop-Job
        $existingJob | Remove-Job -Force
    }
    
    # Start tunnel in background job
    $scriptBlock = {
        minikube tunnel --profile=osdfir --cleanup
    }
    
    Start-Job -Name "minikube-tunnel" -ScriptBlock $scriptBlock | Out-Null
    Start-Sleep -Seconds 3
    
    $tunnelJob = Get-Job -Name "minikube-tunnel"
    if ($tunnelJob -and $tunnelJob.State -eq "Running") {
        Write-Host "[OK] Minikube tunnel started in background" -ForegroundColor $Colors.Success
        Write-Host "LoadBalancer services will be accessible on localhost" -ForegroundColor $Colors.Warning
    } else {
        Write-Host "[WARNING] Tunnel may not have started properly" -ForegroundColor $Colors.Warning
        Write-Host "You may need to run 'minikube tunnel --profile=osdfir' manually" -ForegroundColor $Colors.Warning
    }
}

function Stop-MinikubeTunnel {
    $tunnelJob = Get-Job -Name "minikube-tunnel" -ErrorAction SilentlyContinue
    if ($tunnelJob) {
        Write-Host "Stopping Minikube tunnel..." -ForegroundColor $Colors.Warning
        $tunnelJob | Stop-Job
        $tunnelJob | Remove-Job -Force
        Write-Host "[OK] Tunnel stopped" -ForegroundColor $Colors.Success
    } else {
        Write-Host "No tunnel job found" -ForegroundColor $Colors.Gray
    }
}

function Remove-MinikubeCluster {
    param([switch]$SkipConfirmation = $false)
    
    Write-Host ""
    Write-Host "Deleting OSDFIR Minikube Cluster..." -ForegroundColor $Colors.Error
    Write-Host "==================================" -ForegroundColor $Colors.Error
    Write-Host ""
    
    # Stop tunnel first
    Stop-MinikubeTunnel
    
    if (-not $Force -and -not $SkipConfirmation) {
        $confirmation = Read-Host "Are you sure you want to delete the 'osdfir' cluster? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-Host "Deletion cancelled." -ForegroundColor $Colors.Warning
            return
        }
    }
    
    Write-Host "Deleting Minikube cluster 'osdfir'..." -ForegroundColor $Colors.Error
    minikube delete --profile=osdfir
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Cluster deleted successfully" -ForegroundColor $Colors.Success
    } else {
        Write-Host "[ERROR] Failed to delete cluster" -ForegroundColor $Colors.Error
    }
}

function Start-DockerDesktop {
    Write-Host "Checking Docker Desktop status..." -ForegroundColor $Colors.Info
    
    if (Test-Docker -Silent) {
        Write-Host "[OK] Docker Desktop is already running" -ForegroundColor $Colors.Success
        return $true
    }
    
    Write-Host "Docker Desktop is not running. Starting..." -ForegroundColor $Colors.Warning
    
    # Try to find Docker Desktop executable
    $dockerDesktopPaths = @(
        "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "${env:LOCALAPPDATA}\Programs\Docker\Docker\Docker Desktop.exe"
    )
    
    $dockerExe = $null
    foreach ($path in $dockerDesktopPaths) {
        if (Test-Path $path) {
            $dockerExe = $path
            break
        }
    }
    
    if (-not $dockerExe) {
        Write-Host "ERROR: Could not find Docker Desktop executable" -ForegroundColor $Colors.Error
        Write-Host "Please start Docker Desktop manually or install it from:" -ForegroundColor $Colors.Warning
        Write-Host "https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor $Colors.Gray
        return $false
    }
    
    try {
        Start-Process -FilePath $dockerExe -WindowStyle Hidden
        
        Write-Host "Waiting for Docker Desktop to start (this may take 2-3 minutes)..." -ForegroundColor $Colors.Info
        $timeout = 180 # 3 minutes
        $elapsed = 0
        
        do {
            Start-Sleep -Seconds 10
            $elapsed += 10
            Write-Host "  Checking Docker status... ($elapsed s elapsed)" -ForegroundColor $Colors.Gray
            
            if (Test-Docker -Silent) {
                Write-Host "[OK] Docker Desktop started successfully!" -ForegroundColor $Colors.Success
                return $true
            }
        } while ($elapsed -lt $timeout)
        
        Write-Host "WARNING: Docker Desktop may still be starting. Please wait and try again." -ForegroundColor $Colors.Warning
        return $false
        
    } catch {
        Write-Host "ERROR: Failed to start Docker Desktop: $($_.Exception.Message)" -ForegroundColor $Colors.Error
        Write-Host "Please start Docker Desktop manually." -ForegroundColor $Colors.Warning
        return $false
    }
}

function Test-MinikubeRunning {
    try {
        $status = minikube status --profile=osdfir -f "{{.Host}}" 2>$null
        return $status -eq "Running"
    } catch {
        return $false
    }
}

function Test-KubectlAccess {
    try {
        kubectl get pods -n $Namespace --no-headers 2>$null | Out-Null
        return $true
    } catch {
        Write-Host "ERROR: Cannot access Kubernetes cluster or namespace '$Namespace'" -ForegroundColor $Colors.Error
        Write-Host "TIP: Ensure Minikube is running and kubectl context is set." -ForegroundColor $Colors.Warning
        return $false
    }
}

function Show-MinikubeStatus {
    Show-Header "Minikube Cluster Status"
    
    if (-not (Test-MinikubeRunning)) {
        Write-Host "Minikube cluster 'osdfir' is not running" -ForegroundColor $Colors.Error
        Write-Host "TIP: Run .\manage-osdfir-lab.ps1 deploy to start the full environment" -ForegroundColor $Colors.Info
        return
    }
    
    Write-Host "Cluster Status:" -ForegroundColor $Colors.Success
    minikube status --profile=osdfir
    
    Write-Host ""
    Write-Host "Cluster Resources:" -ForegroundColor $Colors.Success
    kubectl top nodes 2>$null
    
    Write-Host ""
    Write-Host "Minikube Tunnel Job:" -ForegroundColor $Colors.Success
    $tunnelJob = Get-Job -Name "minikube-tunnel" -ErrorAction SilentlyContinue
    if ($tunnelJob) {
        $status = switch ($tunnelJob.State) {
            "Running" { "[RUNNING]" }
            "Completed" { "[STOPPED]" }
            "Failed" { "[FAILED]" }
            default { "[UNKNOWN]" }
        }
        $color = switch ($tunnelJob.State) {
            "Running" { $Colors.Success }
            "Failed" { $Colors.Error }
            default { $Colors.Warning }
        }
        Write-Host "  $status Minikube tunnel" -ForegroundColor $color
    } else {
        Write-Host "  [NOT RUNNING] Minikube tunnel" -ForegroundColor $Colors.Warning
    }
}

function Show-OllamaStatus {
    Show-Header "Ollama AI Model Status"
    
    if (-not (Test-KubectlAccess)) {
        return
    }
    
    # Check Ollama pod status
    Write-Host "Ollama Pod Status:" -ForegroundColor $Colors.Success
    $ollamaPod = kubectl get pods -n $Namespace -l app=ollama --no-headers 2>$null
    if ($ollamaPod) {
        $parts = $ollamaPod -split '\s+'
        $name = $parts[0]
        $status = $parts[2]
        if ($status -eq "Running") {
            Write-Host "  [OK] $name" -ForegroundColor $Colors.Success
        } else {
            Write-Host "  [ERROR] $name ($status)" -ForegroundColor $Colors.Error
        }
    } else {
        Write-Host "  [ERROR] Ollama pod not found" -ForegroundColor $Colors.Error
        return
    }
    
    # Check available models
    Write-Host ""
    Write-Host "Available Models:" -ForegroundColor $Colors.Success
    $availableModels = @()
    try {
        $modelOutput = kubectl exec -n $Namespace $name -- ollama list 2>$null
        if ($modelOutput) {
            $lines = $modelOutput -split "`n"
            $modelLines = $lines | Where-Object { $_ -match "^\w+.*\d+\s+(GB|MB|KB)" }
            
            if ($modelLines.Count -gt 0) {
                foreach ($line in $modelLines) {
                    $parts = $line -split '\s+'
                    $modelName = $parts[0]
                    $modelSize = "$($parts[2]) $($parts[3])"
                    $availableModels += $modelName
                    Write-Host "  [OK] $modelName (Size: $modelSize)" -ForegroundColor $Colors.Success
                }
            } else {
                Write-Host "  [INFO] No models found" -ForegroundColor $Colors.Warning
            }
        } else {
            Write-Host "  [ERROR] Unable to retrieve model list" -ForegroundColor $Colors.Error
        }
    } catch {
        Write-Host "  [ERROR] Failed to check models: $($_.Exception.Message)" -ForegroundColor $Colors.Error
    }
    
    # Test AI functionality if models available
    if ($availableModels.Count -gt 0) {
        Write-Host ""
        Write-Host "AI Functionality Test:" -ForegroundColor $Colors.Success
        $testModel = $availableModels[0]
        try {
            Write-Host "  Testing model '$testModel' with forensic prompt..." -ForegroundColor $Colors.Info
            $testPrompt = "List 3 common digital forensics file types. Answer with just the file types."
            $promptResult = kubectl exec -n $Namespace $name -- ollama run $testModel "$testPrompt" 2>$null
            
            if ($promptResult -and $promptResult.Length -gt 10) {
                Write-Host "  [OK] AI model is responding to prompts" -ForegroundColor $Colors.Success
                Write-Host "  Sample response: $($promptResult.Substring(0, [Math]::Min(80, $promptResult.Length)))..." -ForegroundColor $Colors.Gray
            } else {
                Write-Host "  [ERROR] AI model not responding properly" -ForegroundColor $Colors.Error
            }
        } catch {
            Write-Host "  [WARNING] Unable to test AI functionality: $($_.Exception.Message)" -ForegroundColor $Colors.Warning
        }
    }
}

function Show-Status {
    Show-Header "OSDFIR Deployment Status"
    
    # Check Minikube first
    if (-not (Test-MinikubeRunning)) {
        Write-Host "Minikube cluster 'osdfir' is not running" -ForegroundColor $Colors.Error
        Write-Host "TIP: Run .\manage-osdfir-lab.ps1 deploy to start the full environment" -ForegroundColor $Colors.Info
        return
    }
    
    # Test kubectl access
    if (-not (Test-KubectlAccess)) {
        return
    }
    
    # Check Helm release
    Write-Host "Helm Release Status:" -ForegroundColor $Colors.Success
    try {
        $release = helm list -n $Namespace -o json | ConvertFrom-Json | Where-Object { $_.name -eq $ReleaseName }
        if ($release) {
            Write-Host "  [OK] Release '$ReleaseName' is $($release.status)" -ForegroundColor $Colors.Success
        } else {
            Write-Host "  [ERROR] Release '$ReleaseName' not found" -ForegroundColor $Colors.Error
        }
    } catch {
        Write-Host "  [ERROR] Unable to check Helm releases" -ForegroundColor $Colors.Error
    }
    
    # Check pods
    Write-Host ""
    Write-Host "Pod Status:" -ForegroundColor $Colors.Success
    $pods = kubectl get pods -n $Namespace --no-headers 2>$null
    if ($pods) {
        $runningPods = 0
        $totalPods = 0
        
        $pods | ForEach-Object {
            $totalPods++
            $parts = $_ -split '\s+'
            $name = $parts[0]
            $ready = $parts[1]
            $status = $parts[2]
            
            if ($status -eq "Running" -and $ready -like "*/*") {
                $readyParts = $ready -split '/'
                if ($readyParts[0] -eq $readyParts[1]) {
                    $runningPods++
                    Write-Host "  [OK] $name" -ForegroundColor $Colors.Success
                } else {
                    Write-Host "  [WAIT] $name ($ready)" -ForegroundColor $Colors.Warning
                }
            } else {
                Write-Host "  [ERROR] $name ($status)" -ForegroundColor $Colors.Error
            }
        }
        
        Write-Host ""
        Write-Host "Summary: $runningPods/$totalPods pods running" -ForegroundColor $Colors.Info
    } else {
        Write-Host "  No pods found in namespace '$Namespace'" -ForegroundColor $Colors.Warning
    }
    
    # Check port forwarding jobs
    Write-Host ""
    Write-Host "Port Forwarding Jobs:" -ForegroundColor $Colors.Success
    $osdfirJobs = Get-Job | Where-Object { $_.Name -like "pf-*" }
    
    if ($osdfirJobs.Count -eq 0) {
        Write-Host "  No port forwarding jobs running" -ForegroundColor $Colors.Warning
        Write-Host "  TIP: Run .\manage-osdfir-lab.ps1 start" -ForegroundColor $Colors.Info
    } else {
        foreach ($job in $osdfirJobs) {
            $serviceName = $job.Name -replace "pf-", ""
            $status = switch ($job.State) {
                "Running" { "[RUNNING]" }
                "Completed" { "[STOPPED]" }
                "Failed" { "[FAILED]" }
                "Stopped" { "[STOPPED]" }
                default { "[UNKNOWN]" }
            }
            
            $color = switch ($job.State) {
                "Running" { $Colors.Success }
                "Completed" { $Colors.Warning }
                "Failed" { $Colors.Error }
                "Stopped" { $Colors.Warning }
                default { $Colors.Gray }
            }
            
            Write-Host "  $status $serviceName" -ForegroundColor $color
        }
    }
}

function Start-Services {
    Show-Header "Starting OSDFIR Services"
    
    # Check prerequisites
    if (-not (Test-MinikubeRunning)) {
        Write-Host "ERROR: Minikube cluster is not running" -ForegroundColor $Colors.Error
        Write-Host "TIP: Run .\manage-osdfir-lab.ps1 deploy to start the full environment" -ForegroundColor $Colors.Info
        return
    }
    
    if (-not (Test-KubectlAccess)) {
        return
    }
    
    Write-Host "Checking service availability..." -ForegroundColor $Colors.Info
    
    $services = @(
        @{Name="Timesketch"; Service="$ReleaseName-timesketch"; Port="5000"},
        @{Name="OpenRelik-UI"; Service="$ReleaseName-openrelik"; Port="8711"},
        @{Name="OpenRelik-API"; Service="$ReleaseName-openrelik-api"; Port="8710"}
    )
    
    $availableServices = @()
    foreach ($svc in $services) {
        $null = kubectl get service $svc.Service -n $Namespace --no-headers 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] $($svc.Name) service is available" -ForegroundColor $Colors.Success
            $availableServices += $svc
        } else {
            Write-Host "  [ERROR] $($svc.Name) service not found" -ForegroundColor $Colors.Error
        }
    }
    
    if ($availableServices.Count -eq 0) {
        Write-Host "ERROR: No OSDFIR services are available. Please check your deployment." -ForegroundColor $Colors.Error
        return
    }
    
    Write-Host ""
    Write-Host "Starting port forwarding as background jobs..." -ForegroundColor $Colors.Info
    
    # Stop existing port forwarding jobs
    $existingJobs = Get-Job | Where-Object { $_.Name -like "pf-*" }
    if ($existingJobs) {
        Write-Host "Stopping existing jobs..." -ForegroundColor $Colors.Warning
        $existingJobs | Stop-Job
        $existingJobs | Remove-Job -Force
    }
    
    foreach ($svc in $availableServices) {
        $jobName = "pf-$($svc.Name)"
        Write-Host "  Starting $($svc.Name) on port $($svc.Port)..." -ForegroundColor $Colors.Success
        
        $scriptBlock = {
            param($service, $namespace, $port)
            kubectl port-forward -n $namespace "svc/$service" "${port}:${port}"
        }
        
        Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList $svc.Service, $Namespace, $svc.Port | Out-Null
        Start-Sleep -Seconds 1
    }
    
    Write-Host ""
    Write-Host "Waiting for port forwarding to initialize..." -ForegroundColor $Colors.Info
    Start-Sleep -Seconds 5
    
    Write-Host ""
    Write-Host "OSDFIR Services Available:" -ForegroundColor $Colors.Success
    foreach ($svc in $availableServices) {
        Write-Host "  $($svc.Name): http://localhost:$($svc.Port)" -ForegroundColor $Colors.Header
    }
    
    Write-Host ""
    Write-Host "Port forwarding is now active!" -ForegroundColor $Colors.Success
    Write-Host "TIP: Use .\manage-osdfir-lab.ps1 creds to get login credentials" -ForegroundColor $Colors.Info
}

function Get-ServiceCredential {
    param($ServiceName, $SecretName, $SecretKey, $Username, $ServiceUrl)
    
    Write-Host "$ServiceName Credentials:" -ForegroundColor $Colors.Header
    Write-Host "  Service URL: $ServiceUrl" -ForegroundColor $Colors.Success
    Write-Host "  Username:    $Username" -ForegroundColor $Colors.Success
    
    try {
        $password = kubectl get secret --namespace $Namespace $SecretName -o jsonpath="{.data.$SecretKey}" 2>$null
        
        if ($password) {
            $decodedPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($password))
            Write-Host "  Password:    $decodedPassword" -ForegroundColor $Colors.Success
        } else {
            Write-Host "  Password:    [Secret not found or not accessible]" -ForegroundColor $Colors.Error
        }
    } catch {
        Write-Host "  Password:    [Error retrieving secret]" -ForegroundColor $Colors.Error
    }
    
    Write-Host ""
}

function Show-Credentials {
    Show-Header "OSDFIR Service Credentials"
    
    # Check kubectl access
    if (-not (Test-KubectlAccess)) {
        return
    }
    
    Write-Host "Retrieving credentials for release '$ReleaseName' in namespace '$Namespace'..." -ForegroundColor $Colors.Info
    Write-Host ""
    
    # Get credentials based on service parameter
    switch ($Service) {
        "timesketch" {
            Get-ServiceCredential -ServiceName "Timesketch" -SecretName "$ReleaseName-timesketch-secret" -SecretKey "timesketch-user" -Username "timesketch" -ServiceUrl "http://localhost:5000"
        }
        
        "openrelik" {
            Get-ServiceCredential -ServiceName "OpenRelik" -SecretName "$ReleaseName-openrelik-secret" -SecretKey "openrelik-user" -Username "openrelik" -ServiceUrl "http://localhost:8711"
        }
        
        "all" {
            # Check which services are actually deployed
            $timesketchSecret = kubectl get secret --namespace $Namespace "$ReleaseName-timesketch-secret" 2>$null
            if ($timesketchSecret) {
                Get-ServiceCredential -ServiceName "Timesketch" -SecretName "$ReleaseName-timesketch-secret" -SecretKey "timesketch-user" -Username "timesketch" -ServiceUrl "http://localhost:5000"
            }
            
            $openrelikSecret = kubectl get secret --namespace $Namespace "$ReleaseName-openrelik-secret" 2>$null
            if ($openrelikSecret) {
                Get-ServiceCredential -ServiceName "OpenRelik" -SecretName "$ReleaseName-openrelik-secret" -SecretKey "openrelik-user" -Username "openrelik" -ServiceUrl "http://localhost:8711"
            }
            
            if (-not ($timesketchSecret -or $openrelikSecret)) {
                Write-Host "ERROR: No credential secrets found for release '$ReleaseName' in namespace '$Namespace'" -ForegroundColor $Colors.Error
            }
        }
    }
    
    Write-Host "NOTE: Change default credentials in production environments!" -ForegroundColor $Colors.Warning
}

function Show-Logs {
    Show-Header "OSDFIR Service Logs"
    if (-not (Test-KubectlAccess)) {
        return
    }
    Write-Host "Recent logs from key services:" -ForegroundColor $Colors.Info
    Write-Host ""
    
    $keyServices = @("openrelik-api", "timesketch", "ollama")
    foreach ($serviceName in $keyServices) {
        $pods = kubectl get pods -n $Namespace --no-headers 2>$null | Where-Object { $_ -match $serviceName }
        if ($pods) {
            $podName = ($pods[0] -split '\s+')[0]
            Write-Host "Recent logs for $podName" -ForegroundColor $Colors.Info
            Write-Host "------------------------" -ForegroundColor $Colors.Gray
            kubectl logs $podName -n $Namespace --tail=10 2>$null
        }
        Write-Host ""
    }
}

function Show-Helm {
    Show-Header "Helm Releases and Status"
    if (-not (Test-KubectlAccess)) {
        return
    }
    helm list -n $Namespace
    Write-Host ""
    Write-Host "Release Status:" -ForegroundColor $Colors.Success
    helm status $ReleaseName -n $Namespace
}

function Show-Storage {
    Show-Header "PV Storage Utilization"
    if (-not (Test-KubectlAccess)) { return }
    
    # Get PVC information
    Write-Host "Persistent Volume Claims:" -ForegroundColor $Colors.Success
    kubectl get pvc -n $Namespace
    
    Write-Host ""
    Write-Host "Storage Usage by Pod:" -ForegroundColor $Colors.Success
    
    # Basic storage check for each pod
    $pods = kubectl get pods -n $Namespace --no-headers 2>$null
    foreach ($pod in $pods) {
        $podName = ($pod -split '\s+')[0]
        Write-Host "Pod: $podName" -ForegroundColor $Colors.Info
        $df = kubectl exec -n $Namespace $podName -- df -h / 2>$null | Select-Object -Last 1
        if ($df) {
            Write-Host "  Root filesystem: $df" -ForegroundColor $Colors.Success
        }
        Write-Host ""
    }
}

function Start-FullDeployment {
    Show-Header "Full OSDFIR Deployment"
    
    if (-not (Test-Prerequisites)) {
        return
    }
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute the following steps:" -ForegroundColor $Colors.Warning
        Write-Host "1. Start Docker Desktop (if not running)" -ForegroundColor $Colors.Info
        Write-Host "2. Start Minikube cluster with tunnel" -ForegroundColor $Colors.Info
        Write-Host "3. Initialize and apply Terraform configuration" -ForegroundColor $Colors.Info
        Write-Host "4. Start port forwarding for services" -ForegroundColor $Colors.Info
        return
    }
    
    # Step 1: Ensure Docker Desktop is running
    Write-Host "Step 1: Ensuring Docker Desktop is running..." -ForegroundColor $Colors.Info
    if (-not (Start-DockerDesktop)) {
        Write-Host "ERROR: Could not start Docker Desktop" -ForegroundColor $Colors.Error
        return
    }
    
    # Step 2: Start Minikube
    Write-Host ""
    Write-Host "Step 2: Starting Minikube cluster..." -ForegroundColor $Colors.Info
    if (-not (Start-MinikubeCluster)) {
        Write-Host "ERROR: Failed to start Minikube" -ForegroundColor $Colors.Error
        return
    }
    
    # Start tunnel after successful cluster start
    Start-MinikubeTunnel
    
    # Step 3: Deploy with Terraform
    Write-Host ""
    Write-Host "Step 3: Deploying OSDFIR with Terraform..." -ForegroundColor $Colors.Info
    Push-Location "$PSScriptRoot\..\terraform"
    try {
        terraform init
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Terraform init failed" -ForegroundColor $Colors.Error
            return
        }
        
        terraform apply -auto-approve
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Terraform apply failed" -ForegroundColor $Colors.Error
            return
        }
    } finally {
        Pop-Location
    }
    
    # Step 4: Wait for pods to be ready
    Write-Host ""
    Write-Host "Step 4: Waiting for pods to be ready..." -ForegroundColor $Colors.Info
    $timeout = 600  # 10 minutes
    $elapsed = 0
    do {
        Start-Sleep -Seconds 20
        $elapsed += 20
        $pods = kubectl get pods -n $Namespace --no-headers 2>$null
        $runningPods = ($pods | Where-Object { $_ -match "Running" -and $_ -match "1/1" }).Count
        $runningPods += ($pods | Where-Object { $_ -match "Running" -and $_ -match "2/2" }).Count
        $runningPods += ($pods | Where-Object { $_ -match "Running" -and $_ -match "3/3" }).Count
        $totalPods = ($pods | Measure-Object).Count
        Write-Host "  Pods ready: $runningPods/$totalPods ($elapsed seconds elapsed)" -ForegroundColor $Colors.Info
        
        # Check if Ollama is downloading model
        $ollamaPod = kubectl get pods -n $Namespace -l app=ollama --no-headers 2>$null
        if ($ollamaPod -and $ollamaPod -match "Init") {
            $podName = ($ollamaPod -split '\s+')[0]
            try {
                $initLogs = kubectl logs $podName -c model-puller -n $Namespace --tail=3 2>$null
                if ($initLogs -and $initLogs -match "Pulling model|pulling manifest|downloading") {
                    $lastLine = ($initLogs -split "`n")[-1].Trim()
                    if ($lastLine) {
                        # Clean up Unicode box-drawing characters and other display artifacts
                        $cleanedLine = $lastLine -replace '[^\x20-\x7E]', '' -replace '\s+', ' '
                        # Extract meaningful information from progress lines
                        if ($cleanedLine -match "pulling (\w+):\s+(\d+%)\s+(.+)") {
                            Write-Host "  Ollama: Downloading model layer - $($matches[2]) complete" -ForegroundColor $Colors.Warning
                        } elseif ($cleanedLine -match "pulling manifest") {
                            Write-Host "  Ollama: Downloading model manifest..." -ForegroundColor $Colors.Warning
                        } elseif ($cleanedLine -match "downloading") {
                            Write-Host "  Ollama: Downloading AI model..." -ForegroundColor $Colors.Warning
                        } else {
                            Write-Host "  Ollama: Downloading AI model... This may take several minutes." -ForegroundColor $Colors.Warning
                        }
                    } else {
                        Write-Host "  Ollama is downloading AI model... This may take several minutes." -ForegroundColor $Colors.Warning
                    }
                } elseif ($initLogs -and $initLogs -match "already exists, skipping download") {
                    Write-Host "  Ollama: Model already cached, initializing..." -ForegroundColor $Colors.Success
                } else {
                    Write-Host "  Ollama is initializing AI model..." -ForegroundColor $Colors.Warning
                }
            } catch {
                Write-Host "  Ollama is downloading AI model... This may take several minutes." -ForegroundColor $Colors.Warning
            }
        }
    } while ($runningPods -lt $totalPods -and $elapsed -lt $timeout)
    
    if ($runningPods -lt $totalPods) {
        Write-Host "WARNING: Not all pods are ready after $timeout seconds" -ForegroundColor $Colors.Warning
        Write-Host "You can check status with: .\manage-osdfir-lab.ps1 status" -ForegroundColor $Colors.Info
    }
    
    # Step 5: Start services
    Write-Host ""
    Write-Host "Step 5: Starting port forwarding..." -ForegroundColor $Colors.Info
    Start-Services
    
    Write-Host ""
    Write-Host "Deployment completed!" -ForegroundColor $Colors.Success
    Write-Host "Use .\manage-osdfir-lab.ps1 creds to get login credentials" -ForegroundColor $Colors.Info
    Write-Host "Use .\manage-osdfir-lab.ps1 ollama to check AI model status" -ForegroundColor $Colors.Info
}

function Start-SmartCleanup {
    Show-Header "Smart OSDFIR Cleanup (Preserves AI Models & Data)"
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute the following steps:" -ForegroundColor $Colors.Warning
        Write-Host "1. Stop all port forwarding jobs" -ForegroundColor $Colors.Info
        Write-Host "2. Destroy Terraform resources" -ForegroundColor $Colors.Info
        Write-Host "3. Preserve Minikube cluster and persistent data" -ForegroundColor $Colors.Header
        return
    }
    
    if (-not $Force) {
        Write-Host "This will clean up OSDFIR services but preserve:" -ForegroundColor $Colors.Info
        Write-Host "  - AI models (no re-download needed)" -ForegroundColor $Colors.Success
        Write-Host "  - Database data" -ForegroundColor $Colors.Success
        Write-Host "  - Minikube cluster" -ForegroundColor $Colors.Success
        Write-Host ""
        $confirmation = Read-Host "Continue with smart cleanup? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-Host "Cleanup cancelled." -ForegroundColor $Colors.Warning
            return
        }
    }
    
    # Step 1: Stop services
    Write-Host "Step 1: Stopping port forwarding jobs..." -ForegroundColor $Colors.Info
    $pfJobs = Get-Job | Where-Object { $_.Name -like "pf-*" }
    if ($pfJobs) {
        $pfJobs | Stop-Job
        $pfJobs | Remove-Job -Force
        Write-Host "Port forwarding jobs stopped." -ForegroundColor $Colors.Success
    }
    
    # Step 2: Destroy Terraform
    Write-Host ""
    Write-Host "Step 2: Destroying Terraform resources..." -ForegroundColor $Colors.Info
    Push-Location "$PSScriptRoot\..\terraform"
    try {
        terraform destroy -auto-approve
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Terraform destroy had issues" -ForegroundColor $Colors.Warning
        }
    } finally {
        Pop-Location
    }
    
    Write-Host ""
    Write-Host "Smart cleanup completed!" -ForegroundColor $Colors.Success
    Write-Host "[OK] Services removed" -ForegroundColor $Colors.Success
    Write-Host "[OK] AI models preserved (next deploy will be faster)" -ForegroundColor $Colors.Header
    Write-Host "[OK] Database data preserved" -ForegroundColor $Colors.Header
    Write-Host "[OK] Minikube cluster ready for redeployment" -ForegroundColor $Colors.Header
}

function Start-FullCleanup {
    Show-Header "COMPLETE OSDFIR Destruction (Nuclear Option)"
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute the following steps:" -ForegroundColor $Colors.Error
        Write-Host "1. Stop all port forwarding jobs" -ForegroundColor $Colors.Info
        Write-Host "2. Destroy Terraform resources" -ForegroundColor $Colors.Info
        Write-Host "3. Delete entire Minikube cluster (including AI models & data)" -ForegroundColor $Colors.Error
        return
    }
    
    Write-Host ""
    Write-Host "WARNING: COMPLETE DESTRUCTION MODE" -ForegroundColor $Colors.Error -BackgroundColor Black
    Write-Host ""
    Write-Host "This will permanently destroy:" -ForegroundColor $Colors.Error
    Write-Host "  - All OSDFIR services" -ForegroundColor $Colors.Warning
    Write-Host "  - All database data" -ForegroundColor $Colors.Warning  
    Write-Host "  - All AI models (1.6GB+ will need re-download)" -ForegroundColor $Colors.Warning
    Write-Host "  - Entire Minikube cluster" -ForegroundColor $Colors.Warning
    Write-Host "  - All persistent volumes and data" -ForegroundColor $Colors.Warning
    Write-Host ""
    Write-Host "TIP: Consider 'teardown-lab' instead to preserve AI models and data" -ForegroundColor $Colors.Info
    Write-Host ""
    
    if (-not $Force) {
        $confirmation = Read-Host "Type 'DESTROY' in all caps to confirm complete destruction"
        if ($confirmation -ne "DESTROY") {
            Write-Host "Complete destruction cancelled." -ForegroundColor $Colors.Success
            Write-Host "TIP: Use 'teardown-lab' for smart cleanup that preserves data" -ForegroundColor $Colors.Info
            return
        }
        
        # Double confirmation for nuclear option
        $finalConfirmation = Read-Host "Final confirmation - this will delete EVERYTHING. Continue? (yes/no)"
        if ($finalConfirmation -ne "yes") {
            Write-Host "Complete destruction cancelled." -ForegroundColor $Colors.Success
            return
        }
    }
    
    # Step 1: Stop services
    Write-Host "Step 1: Stopping port forwarding jobs..." -ForegroundColor $Colors.Info
    $pfJobs = Get-Job | Where-Object { $_.Name -like "pf-*" }
    if ($pfJobs) {
        $pfJobs | Stop-Job
        $pfJobs | Remove-Job -Force
        Write-Host "Port forwarding jobs stopped." -ForegroundColor $Colors.Success
    }
    
    # Step 2: Destroy Terraform
    Write-Host ""
    Write-Host "Step 2: Destroying Terraform resources..." -ForegroundColor $Colors.Info
    Push-Location "$PSScriptRoot\..\terraform"
    try {
        terraform destroy -auto-approve
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Terraform destroy had issues" -ForegroundColor $Colors.Warning
        }
    } finally {
        Pop-Location
    }
    
    # Step 3: Delete Minikube cluster completely
    Write-Host ""
    Write-Host "Step 3: Deleting entire Minikube cluster..." -ForegroundColor $Colors.Error
    # Skip confirmation since user already confirmed complete destruction
    $script:Force = $true
    Remove-MinikubeCluster
    $script:Force = $Force  # Restore original Force setting
    
    Write-Host ""
    Write-Host "Complete destruction finished!" -ForegroundColor $Colors.Error
    Write-Host "Everything has been permanently removed." -ForegroundColor $Colors.Warning
    Write-Host "Next deployment will start completely fresh (including AI model download)." -ForegroundColor $Colors.Info
}

function Restart-Deployment {
    Show-Header "Reinstalling OSDFIR Deployment"
    
    if (-not (Test-Prerequisites)) {
        return
    }
    
    if (-not (Test-MinikubeRunning)) {
        Write-Host "ERROR: Minikube cluster is not running" -ForegroundColor $Colors.Error
        Write-Host "TIP: Run .\manage-osdfir-lab.ps1 deploy to start the full environment" -ForegroundColor $Colors.Info
        return
    }
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute the following steps:" -ForegroundColor $Colors.Warning
        Write-Host "1. Stop all port forwarding jobs" -ForegroundColor $Colors.Info
        Write-Host "2. Preserve database passwords" -ForegroundColor $Colors.Info
        Write-Host "3. Uninstall existing Helm release" -ForegroundColor $Colors.Info
        Write-Host "4. Wait for cleanup to complete" -ForegroundColor $Colors.Info
        Write-Host "5. Apply Terraform configuration with preserved passwords" -ForegroundColor $Colors.Info
        Write-Host "6. Wait for pods to be ready" -ForegroundColor $Colors.Info
        Write-Host "7. Start port forwarding" -ForegroundColor $Colors.Info
        return
    }
    
    if (-not $Force) {
        $confirmation = Read-Host "This will uninstall and reinstall the '$ReleaseName' Helm release in namespace '$Namespace'. Continue? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-Host "Reinstall cancelled." -ForegroundColor $Colors.Warning
            return
        }
    }
    
    # Step 1: Stop port forwarding jobs
    Write-Host "Step 1: Stopping port forwarding jobs..." -ForegroundColor $Colors.Info
    $pfJobs = Get-Job | Where-Object { $_.Name -like "pf-*" }
    if ($pfJobs) {
        $pfJobs | Stop-Job
        $pfJobs | Remove-Job -Force
        Write-Host "Port forwarding jobs stopped." -ForegroundColor $Colors.Success
    }
    
    # Step 2: Preserve database passwords
    Write-Host ""
    Write-Host "Step 2: Preserving database passwords..." -ForegroundColor $Colors.Info
    $preservedPasswords = @{}
    
    # Try to get existing passwords from secrets
    try {
        $timesketchPwd = kubectl get secret osdfir-lab-timesketch-secret -n $Namespace -o jsonpath="{.data.postgres-user}" 2>$null
        if ($timesketchPwd -and $timesketchPwd.Length -gt 0) {
            $preservedPasswords['timesketch'] = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($timesketchPwd))
            Write-Host "  [OK] Preserved Timesketch database password" -ForegroundColor $Colors.Success
        } else {
            Write-Host "  [SKIP] Could not preserve Timesketch password (will generate new)" -ForegroundColor $Colors.Warning
        }
    } catch {
        Write-Host "  [SKIP] Could not preserve Timesketch password (will generate new)" -ForegroundColor $Colors.Warning
    }
    
    try {
        $openrelikPwd = kubectl get secret osdfir-lab-openrelik-secret -n $Namespace -o jsonpath="{.data.postgres-user}" 2>$null
        if ($openrelikPwd -and $openrelikPwd.Length -gt 0) {
            $preservedPasswords['openrelik'] = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($openrelikPwd))
            Write-Host "  [OK] Preserved OpenRelik database password" -ForegroundColor $Colors.Success
        } else {
            Write-Host "  [SKIP] Could not preserve OpenRelik password (will generate new)" -ForegroundColor $Colors.Warning
        }
    } catch {
        Write-Host "  [SKIP] Could not preserve OpenRelik password (will generate new)" -ForegroundColor $Colors.Warning
    }
    
    # Step 3: Uninstall existing Helm release
    Write-Host ""
    Write-Host "Step 3: Uninstalling existing Helm release..." -ForegroundColor $Colors.Info
    
    # Check if release exists
    $releaseExists = $false
    try {
        $release = helm list -n $Namespace -o json | ConvertFrom-Json | Where-Object { $_.name -eq $ReleaseName }
        if ($release) {
            $releaseExists = $true
            Write-Host "Found existing release '$ReleaseName' with status: $($release.status)" -ForegroundColor $Colors.Info
        }
    } catch {
        Write-Host "Unable to check existing releases, proceeding with reinstall..." -ForegroundColor $Colors.Warning
    }
    
    if ($releaseExists) {
        Write-Host "Uninstalling release '$ReleaseName'..." -ForegroundColor $Colors.Warning
        helm uninstall $ReleaseName -n $Namespace
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Release uninstalled successfully." -ForegroundColor $Colors.Success
        } else {
            Write-Host "WARNING: Uninstall may have had issues, proceeding anyway..." -ForegroundColor $Colors.Warning
        }
        
        # Step 4: Wait for cleanup
        Write-Host ""
        Write-Host "Step 4: Waiting for resources to be cleaned up..." -ForegroundColor $Colors.Info
        $cleanupTimeout = 120
        $elapsed = 0
        do {
            Start-Sleep -Seconds 5
            $elapsed += 5
            $pods = kubectl get pods -n $Namespace --no-headers 2>$null
            $remainingPods = ($pods | Where-Object { $_ -match $ReleaseName }).Count
            Write-Host "  Remaining pods: $remainingPods ($elapsed s elapsed)" -ForegroundColor $Colors.Info
        } while ($remainingPods -gt 0 -and $elapsed -lt $cleanupTimeout)
        
        if ($remainingPods -gt 0) {
            Write-Host "WARNING: Some pods may still be terminating, proceeding anyway..." -ForegroundColor $Colors.Warning
        } else {
            Write-Host "Cleanup completed." -ForegroundColor $Colors.Success
        }
    } else {
        Write-Host "No existing release found, proceeding with fresh install..." -ForegroundColor $Colors.Info
    }
    
    # Step 5: Create temporary values file with preserved passwords
    Write-Host ""
    Write-Host "Step 5: Creating temporary values file with preserved passwords..." -ForegroundColor $Colors.Info
    $tempValuesFile = "$PSScriptRoot\..\terraform\temp-preserved-passwords.yaml"
    $tempValuesContent = @"
# Temporary values file for preserved passwords during reinstall
"@
    
    if ($preservedPasswords.ContainsKey('timesketch')) {
        $tempValuesContent += @"

timesketch:
  postgres:
    password: "$($preservedPasswords['timesketch'])"
"@
        Write-Host "  Added preserved Timesketch password to values" -ForegroundColor $Colors.Success
    }
    
    if ($preservedPasswords.ContainsKey('openrelik')) {
        $tempValuesContent += @"

openrelik:
  postgres:
    password: "$($preservedPasswords['openrelik'])"
"@
        Write-Host "  Added preserved OpenRelik password to values" -ForegroundColor $Colors.Success
    }
    
    # Write temporary values file
    $tempValuesContent | Out-File -FilePath $tempValuesFile -Encoding UTF8
    
    # Step 6: Reinstall with Terraform using preserved passwords
    Write-Host ""
    Write-Host "Step 6: Reinstalling OSDFIR with Terraform and preserved passwords..." -ForegroundColor $Colors.Info
    Push-Location "$PSScriptRoot\..\terraform"
    try {
        # Modify the Terraform main.tf to include the temp values file
        $originalMainContent = Get-Content "main.tf" -Raw
        $modifiedMainContent = $originalMainContent -replace 'values\s*=\s*\[\s*([^\]]+)\s*\]', 'values = [$1, file("temp-preserved-passwords.yaml")]'
        $modifiedMainContent | Out-File -FilePath "main.tf" -Encoding UTF8
        
        # Run terraform apply to reinstall
        terraform apply -auto-approve
        $terraformResult = $LASTEXITCODE
        
        # Restore original main.tf
        $originalMainContent | Out-File -FilePath "main.tf" -Encoding UTF8
        
        if ($terraformResult -ne 0) {
            Write-Host "ERROR: Terraform apply failed during reinstall" -ForegroundColor $Colors.Error
            return
        }
    } finally {
        Pop-Location
        # Clean up temporary values file
        Remove-Item $tempValuesFile -ErrorAction SilentlyContinue
    }
    
    # Step 7: Wait for pods to be ready
    Write-Host ""
    Write-Host "Step 7: Waiting for pods to be ready..." -ForegroundColor $Colors.Info
    $timeout = 600  # 10 minutes for full startup including AI model download
    $elapsed = 0
    do {
        Start-Sleep -Seconds 20
        $elapsed += 20
        $pods = kubectl get pods -n $Namespace --no-headers 2>$null
        $runningPods = ($pods | Where-Object { $_ -match "Running" -and $_ -match "1/1" }).Count
        $runningPods += ($pods | Where-Object { $_ -match "Running" -and $_ -match "2/2" }).Count
        $runningPods += ($pods | Where-Object { $_ -match "Running" -and $_ -match "3/3" }).Count
        $totalPods = ($pods | Measure-Object).Count
        Write-Host "  Pods ready: $runningPods/$totalPods ($elapsed seconds elapsed)" -ForegroundColor $Colors.Info
        
        # Check if Ollama is downloading model
        $ollamaPod = kubectl get pods -n $Namespace -l app=ollama --no-headers 2>$null
        if ($ollamaPod -and $ollamaPod -match "Init") {
            $podName = ($ollamaPod -split '\s+')[0]
            try {
                $initLogs = kubectl logs $podName -c model-puller -n $Namespace --tail=3 2>$null
                if ($initLogs -and $initLogs -match "Pulling model|pulling manifest|downloading") {
                    $lastLine = ($initLogs -split "`n")[-1].Trim()
                    if ($lastLine) {
                        # Clean up Unicode box-drawing characters and other display artifacts
                        $cleanedLine = $lastLine -replace '[^\x20-\x7E]', '' -replace '\s+', ' '
                        # Extract meaningful information from progress lines
                        if ($cleanedLine -match "pulling (\w+):\s+(\d+%)\s+(.+)") {
                            Write-Host "  Ollama: Downloading model layer - $($matches[2]) complete" -ForegroundColor $Colors.Warning
                        } elseif ($cleanedLine -match "pulling manifest") {
                            Write-Host "  Ollama: Downloading model manifest..." -ForegroundColor $Colors.Warning
                        } elseif ($cleanedLine -match "downloading") {
                            Write-Host "  Ollama: Downloading AI model..." -ForegroundColor $Colors.Warning
                        } else {
                            Write-Host "  Ollama: Downloading AI model... This may take several minutes." -ForegroundColor $Colors.Warning
                        }
                    } else {
                        Write-Host "  Ollama is downloading AI model... This may take several minutes." -ForegroundColor $Colors.Warning
                    }
                } elseif ($initLogs -and $initLogs -match "already exists, skipping download") {
                    Write-Host "  Ollama: Model already cached, initializing..." -ForegroundColor $Colors.Success
                } else {
                    Write-Host "  Ollama is initializing AI model..." -ForegroundColor $Colors.Warning
                }
            } catch {
                Write-Host "  Ollama is downloading AI model... This may take several minutes." -ForegroundColor $Colors.Warning
            }
        }
    } while ($runningPods -lt $totalPods -and $elapsed -lt $timeout)
    
    if ($runningPods -lt $totalPods) {
        Write-Host "WARNING: Not all pods are ready after $timeout seconds" -ForegroundColor $Colors.Warning
        Write-Host "You can check status with: .\manage-osdfir-lab.ps1 status" -ForegroundColor $Colors.Info
    } else {
        Write-Host "All pods are ready!" -ForegroundColor $Colors.Success
    }
    
    # Step 8: Start services
    Write-Host ""
    Write-Host "Step 8: Starting port forwarding..." -ForegroundColor $Colors.Info
    Start-Services
    
    Write-Host ""
    Write-Host "Reinstall completed!" -ForegroundColor $Colors.Success
    if ($preservedPasswords.Count -gt 0) {
        Write-Host "Database passwords were preserved - services should continue working with existing data." -ForegroundColor $Colors.Success
    } else {
        Write-Host "New database passwords were generated - existing data may be inaccessible." -ForegroundColor $Colors.Warning
    }
    Write-Host "Use .\manage-osdfir-lab.ps1 creds to get login credentials" -ForegroundColor $Colors.Info
    Write-Host "Use .\manage-osdfir-lab.ps1 ollama to check AI model status" -ForegroundColor $Colors.Info
}

# Handle -h flag for help
if ($h) {
    $Action = "help"
}

# Main script logic
switch ($Action.ToLower()) {
    "help" { Show-Help }
    "status" { Show-Status }
    "start" { Start-Services }
    "stop" { 
        $pfJobs = Get-Job | Where-Object { $_.Name -like "pf-*" }
        if ($pfJobs.Count -eq 0) {
            Write-Host "No port forwarding jobs found to stop." -ForegroundColor $Colors.Warning
        } else {
            Write-Host "Stopping and removing port forwarding jobs..." -ForegroundColor $Colors.Info
            $pfJobs | Stop-Job
            $pfJobs | Remove-Job -Force
            Write-Host "All port forwarding jobs stopped and removed." -ForegroundColor $Colors.Success
        }
    }
    "restart" { 
        Write-Host "Restarting OSDFIR services..." -ForegroundColor $Colors.Info
        $pfJobs = Get-Job | Where-Object { $_.Name -like "pf-*" }
        if ($pfJobs) {
            $pfJobs | Stop-Job
            $pfJobs | Remove-Job -Force
        }
        Start-Sleep -Seconds 2
        Start-Services
    }
    "logs" { Show-Logs }
    "creds" { Show-Credentials }
    "jobs" { 
        Show-Header "Background Jobs"
        $allJobs = Get-Job | Where-Object { $_.Name -like "pf-*" -or $_.Name -eq "minikube-tunnel" }
        if ($allJobs.Count -eq 0) {
            Write-Host "No OSDFIR-related jobs found." -ForegroundColor $Colors.Warning
        } else {
            foreach ($job in $allJobs) {
                $status = switch ($job.State) {
                    "Running" { "[RUNNING]" }
                    "Completed" { "[STOPPED]" }
                    "Failed" { "[FAILED]" }
                    "Stopped" { "[STOPPED]" }
                    default { "[UNKNOWN]" }
                }
                $color = switch ($job.State) {
                    "Running" { $Colors.Success }
                    "Failed" { $Colors.Error }
                    "Stopped" { $Colors.Warning }
                    default { $Colors.Gray }
                }
                Write-Host "  $status $($job.Name)" -ForegroundColor $color
            }
        }
    }
    "cleanup" { 
        Write-Host "OSDFIR Cleanup - Use with caution!" -ForegroundColor $Colors.Error
        if (-not $Force) {
            $confirmation = Read-Host "Are you sure you want to cleanup OSDFIR resources? (yes/no)"
            if ($confirmation -ne "yes") {
                Write-Host "Cleanup cancelled." -ForegroundColor $Colors.Warning
                return
            }
        }
        Write-Host "Cleaning up OSDFIR jobs..." -ForegroundColor $Colors.Warning
        $allJobs = Get-Job | Where-Object { $_.Name -like "pf-*" -or $_.Name -eq "minikube-tunnel" }
        if ($allJobs) {
            $allJobs | Stop-Job
            $allJobs | Remove-Job -Force
            Write-Host "OSDFIR jobs cleaned up." -ForegroundColor $Colors.Success
        } else {
            Write-Host "No OSDFIR jobs found to clean up." -ForegroundColor $Colors.Info
        }
    }
    "helm" { Show-Helm }
    "uninstall" {
        if (-not $Force) {
            $confirmation = Read-Host "Are you sure you want to uninstall the Helm release '$ReleaseName'? (yes/no)"
            if ($confirmation -ne "yes") {
                Write-Host "Uninstall cancelled." -ForegroundColor $Colors.Warning
                return
            }
        }
        Show-Header "Uninstalling OSDFIR Helm Release"
        helm uninstall $ReleaseName -n $Namespace
    }
    "reinstall" { Restart-Deployment }
    "storage" { Show-Storage }
    "minikube" { Show-MinikubeStatus }
    "docker" { 
        Show-Header "Docker Desktop Management"
        if (Test-Docker) {
            # Show some Docker info
            Write-Host ""
            Write-Host "Docker Info:" -ForegroundColor $Colors.Info
            docker version --format "Client: {{.Client.Version}}"
            docker version --format "Server: {{.Server.Version}}"
        } else {
            Start-DockerDesktop
        }
    }
    "deploy" { Start-FullDeployment }
    "teardown-lab" { Start-SmartCleanup }
    "teardown-lab-all" { Start-FullCleanup }
    "ollama" { Show-OllamaStatus }
    "ollama-test" {
        Show-Header "Ollama AI Prompt Testing"
        
        if (-not (Test-KubectlAccess)) {
            return
        }
        
        $ollamaPod = kubectl get pods -n $Namespace -l app=ollama --no-headers 2>$null
        if (-not $ollamaPod) {
            Write-Host "ERROR: Ollama pod not found" -ForegroundColor $Colors.Error
            return
        }
        
        $name = ($ollamaPod -split '\s+')[0]
        
        # Get available models
        $modelOutput = kubectl exec -n $Namespace $name -- ollama list 2>$null
        $availableModels = @()
        if ($modelOutput) {
            $lines = $modelOutput -split "`n"
            $modelLines = $lines | Where-Object { $_ -match "^\w+.*\d+\s+(GB|MB|KB)" }
            foreach ($line in $modelLines) {
                $parts = $line -split '\s+'
                $availableModels += $parts[0]
            }
        }
        
        if ($availableModels.Count -eq 0) {
            Write-Host "ERROR: No models available for testing" -ForegroundColor $Colors.Error
            return
        }
        
        $testModel = $availableModels[0]
        Write-Host "Testing model: $testModel" -ForegroundColor $Colors.Info
        Write-Host "This may take a few moments for each prompt..." -ForegroundColor $Colors.Warning
        
        # Test prompts with numbering and humorous forensics questions
        $testPrompts = @(
            @{Number=1; Prompt="Tell me a pun about digital forensics. Be creative and funny."},
            @{Number=2; Prompt="Write a haiku about finding deleted files. Make it dramatic and slightly ridiculous."}
        )
        
        $totalPrompts = $testPrompts.Count
        foreach ($promptObj in $testPrompts) {
            Write-Host ""
            Write-Host "Test $($promptObj.Number) of ${totalPrompts}: $($promptObj.Prompt)" -ForegroundColor $Colors.Header
            Write-Host "Response:" -ForegroundColor $Colors.Success
            
            try {
                $response = kubectl exec -n $Namespace $name -- ollama run $testModel "$($promptObj.Prompt)" 2>$null
                if ($response) {
                    Write-Host $response -ForegroundColor $Colors.Info
                } else {
                    Write-Host "No response received" -ForegroundColor $Colors.Warning
                }
            } catch {
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor $Colors.Error
            }
            
            Write-Host ""
        }
        
        Write-Host "AI Prompt Testing Complete!" -ForegroundColor $Colors.Success
        Write-Host "TIP: Use these prompts as examples for integrating AI into your forensic workflows." -ForegroundColor $Colors.Info
    }
    default { Show-Help }
}
