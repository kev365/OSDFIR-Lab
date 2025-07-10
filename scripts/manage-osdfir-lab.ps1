# OSDFIR Lab Management Script
# Unified tool for managing OSDFIR deployment, services, and credentials on Minikube

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("help", "status", "start", "stop", "restart", "logs", "cleanup", "creds", "jobs", "helm", "uninstall", "storage", "minikube", "deploy", "teardown-lab", "ollama", "docker")]
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
    Write-Host "  deploy       - Full deployment (Docker + Minikube + Terraform + Services)"
    Write-Host "  teardown-lab - Full cleanup (Services + Terraform + Minikube)"
    Write-Host "  docker       - Check and start Docker Desktop if needed"
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
    Write-Host ""
    Write-Host "MAINTENANCE:" -ForegroundColor $Colors.Success
    Write-Host "  cleanup      - Clean up OSDFIR deployment"
    Write-Host "  uninstall    - Uninstall the Helm release"
    Write-Host "  help         - Show this help message"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor $Colors.Header
    Write-Host "  -h                Show help (alias for help action)"
    Write-Host "  -ReleaseName      Helm release name (default: osdfir-lab)"
    Write-Host "  -Namespace        Kubernetes namespace (default: osdfir)"
    Write-Host "  -Service          Specific service for creds (all, timesketch, openrelik)"
    Write-Host "  -Force            Force operations without confirmation"
    Write-Host "  -DryRun           Show what would be done without executing"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor $Colors.Header
    Write-Host "  .\manage-osdfir-lab.ps1 -h"
    Write-Host "  .\manage-osdfir-lab.ps1 docker"
    Write-Host "  .\manage-osdfir-lab.ps1 deploy"
    Write-Host "  .\manage-osdfir-lab.ps1 status"
    Write-Host "  .\manage-osdfir-lab.ps1 start"
    Write-Host "  .\manage-osdfir-lab.ps1 creds -Service timesketch"
    Write-Host "  .\manage-osdfir-lab.ps1 logs"
    Write-Host "  .\manage-osdfir-lab.ps1 ollama"
    Write-Host "  .\manage-osdfir-lab.ps1 teardown-lab -Force"
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

# Minikube-specific functions (merged from start-minikube.ps1)

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
    try {
        docker info > $null 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Docker is running" -ForegroundColor $Colors.Success
            return $true
        } else {
            Write-Host "[ERROR] Docker is not running" -ForegroundColor $Colors.Error
            Write-Host "Please start Docker Desktop and try again." -ForegroundColor $Colors.Warning
            return $false
        }
    } catch {
        Write-Host "[ERROR] Docker command not found" -ForegroundColor $Colors.Error
        Write-Host "Please install Docker Desktop and try again." -ForegroundColor $Colors.Warning
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
    if (-not (Test-Docker)) {
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
    Write-Host ""
    Write-Host "Deleting OSDFIR Minikube Cluster..." -ForegroundColor $Colors.Error
    Write-Host "==================================" -ForegroundColor $Colors.Error
    Write-Host ""
    
    # Stop tunnel first
    Stop-MinikubeTunnel
    
    if (-not $Force) {
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

# Existing Docker and testing functions



function Start-DockerDesktop {
    Write-Host "Checking Docker Desktop status..." -ForegroundColor $Colors.Info
    
    if (Test-Docker) {
        Write-Host "[OK] Docker Desktop is already running" -ForegroundColor $Colors.Success
        return $true
    }
    
    Write-Host "Docker Desktop is not running. Attempting to start..." -ForegroundColor $Colors.Warning
    
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
        Write-Host "Starting Docker Desktop..." -ForegroundColor $Colors.Info
        Start-Process -FilePath $dockerExe -WindowStyle Hidden
        
        Write-Host "Waiting for Docker Desktop to start (this may take 1-2 minutes)..." -ForegroundColor $Colors.Info
        $timeout = 120 # 2 minutes
        $elapsed = 0
        
        do {
            Start-Sleep -Seconds 5
            $elapsed += 5
            Write-Host "  Checking Docker status... (${elapsed}s elapsed)" -ForegroundColor $Colors.Gray
            
            if (Test-Docker) {
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
    try {
        $models = kubectl exec -n $Namespace $name -- curl -s http://localhost:11434/api/tags 2>$null
        if ($models) {
            $modelData = $models | ConvertFrom-Json
            foreach ($model in $modelData.models) {
                $sizeGB = [math]::Round($model.size / 1GB, 2)
                Write-Host "  [OK] $($model.name) (Size: $sizeGB GB)" -ForegroundColor $Colors.Success
            }
        } else {
            Write-Host "  [ERROR] Unable to retrieve model list" -ForegroundColor $Colors.Error
        }
    } catch {
        Write-Host "  [ERROR] Failed to check models: $($_.Exception.Message)" -ForegroundColor $Colors.Error
    }
    
    # Check Ollama service connectivity from OpenRelik
    Write-Host ""
    Write-Host "OpenRelik Connectivity Test:" -ForegroundColor $Colors.Success
    $openrelikPod = kubectl get pods -n $Namespace -l app.kubernetes.io/name=openrelik-api --no-headers 2>$null | Select-Object -First 1
    if ($openrelikPod) {
        $apiPodName = ($openrelikPod -split '\s+')[0]
        try {
            $testResult = kubectl exec -n $Namespace $apiPodName -- curl -s http://ollama.osdfir.svc.cluster.local:11434/api/tags 2>$null
            if ($testResult) {
                Write-Host "  [OK] OpenRelik can reach Ollama service" -ForegroundColor $Colors.Success
            } else {
                Write-Host "  [ERROR] OpenRelik cannot reach Ollama service" -ForegroundColor $Colors.Error
            }
        } catch {
            Write-Host "  [WARNING] Unable to test connectivity from OpenRelik" -ForegroundColor $Colors.Warning
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
            Write-Host ""
        }
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
    
    # Fetch all pods in namespace
    $podsJson = kubectl get pods -n $Namespace -o json | ConvertFrom-Json
    foreach ($pod in $podsJson.items) {
        $podName = $pod.metadata.name
        # Inspect each volume for PVC mounts
        foreach ($vol in $pod.spec.volumes) {
            if ($vol.persistentVolumeClaim) {
                $pvcName = $vol.persistentVolumeClaim.claimName
                # Find corresponding mountPath
                $mountObj = $pod.spec.containers[0].volumeMounts | Where-Object { $_.name -eq $vol.name }
                if ($mountObj) {
                    $mountPath = $mountObj.mountPath
                    Write-Host "Pod: $podName" -ForegroundColor $Colors.Info
                    Write-Host "  PVC:       $pvcName" -ForegroundColor $Colors.Success
                    Write-Host "  MountPath: $mountPath" -ForegroundColor $Colors.Success
                    # Run df to get storage info
                    $df = kubectl exec -n $Namespace $podName -- df -h $mountPath 2>$null
                    if ($df) {
                        $lines = $df -split "`n"
                        if ($lines.Length -gt 1) {
                            $info = $lines[1].Trim()
                            $parts = $info -split '\s+'
                            Write-Host "  Filesystem: $($parts[0])" -ForegroundColor $Colors.Success
                            Write-Host "  Size:       $($parts[1])" -ForegroundColor $Colors.Success
                            Write-Host "  Used:       $($parts[2])" -ForegroundColor $Colors.Success
                            Write-Host "  Avail:      $($parts[3])" -ForegroundColor $Colors.Success
                            Write-Host "  Use%:       $($parts[4])" -ForegroundColor $Colors.Success
                        }
                    } else {
                        Write-Host "  Unable to retrieve storage info." -ForegroundColor $Colors.Error
                    }
                    Write-Host ""
                }
            }
        }
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
    $timeout = 600  # Increased timeout for AI model download
    $elapsed = 0
    do {
        Start-Sleep -Seconds 10
        $elapsed += 10
        $pods = kubectl get pods -n $Namespace --no-headers 2>$null
        $runningPods = ($pods | Where-Object { $_ -match "Running" -and $_ -match "1/1|2/2|3/3" }).Count
        $totalPods = ($pods | Measure-Object).Count
        Write-Host "  Pods ready: $runningPods/$totalPods (${elapsed}s elapsed)" -ForegroundColor $Colors.Info
        
        # Check if Ollama is downloading model
        $ollamaPod = kubectl get pods -n $Namespace -l app=ollama --no-headers 2>$null
        if ($ollamaPod -and $ollamaPod -match "Init") {
            Write-Host "  Ollama is downloading AI model... This may take several minutes." -ForegroundColor $Colors.Warning
        }
    } while ($runningPods -lt $totalPods -and $elapsed -lt $timeout)
    
    if ($runningPods -lt $totalPods) {
        Write-Host "WARNING: Not all pods are ready after ${timeout}s" -ForegroundColor $Colors.Warning
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

function Start-FullCleanup {
    Show-Header "Full OSDFIR Cleanup"
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute the following steps:" -ForegroundColor $Colors.Warning
        Write-Host "1. Stop all port forwarding jobs" -ForegroundColor $Colors.Info
        Write-Host "2. Destroy Terraform resources" -ForegroundColor $Colors.Info
        Write-Host "3. Delete Minikube cluster" -ForegroundColor $Colors.Info
        return
    }
    
    if (-not $Force) {
        $confirmation = Read-Host "This will destroy the entire OSDFIR environment. Are you sure? (yes/no)"
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
    
    # Step 3: Delete Minikube
    Write-Host ""
    Write-Host "Step 3: Deleting Minikube cluster..." -ForegroundColor $Colors.Info
    Remove-MinikubeCluster
    
    Write-Host ""
    Write-Host "Cleanup completed!" -ForegroundColor $Colors.Success
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
    "storage" { Show-Storage }
    "minikube" { Show-MinikubeStatus }
    "docker" { 
        Show-Header "Docker Desktop Management"
        if (Test-Docker) {
            Write-Host "[OK] Docker Desktop is running" -ForegroundColor $Colors.Success
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
    "teardown-lab" { Start-FullCleanup }
    "ollama" { Show-OllamaStatus }
    default { Show-Help }
}
