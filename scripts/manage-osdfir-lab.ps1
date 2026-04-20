# OSDFIR Lab Management Script
# Unified tool for managing OSDFIR deployment, services, and credentials on Minikube

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("help", "status", "start", "stop", "restart", "logs", "creds", "jobs", "uninstall", "storage", "minikube", "deploy", "shutdown-lab", "destroy-lab", "ollama", "docker", "mcp-setup")]
    [string]$Action = "help",
    
    [Parameter(Mandatory = $false)]
    [string]$ReleaseName = "osdfir-lab",
    
    [Parameter(Mandatory = $false)]
    [string]$Namespace = "osdfir",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("all", "timesketch", "openrelik", "yeti")]
    [string]$Service = "all",
    
    # Help alias
    [switch]$h = $false,
    
    # Cleanup and deployment options
    [switch]$Force = $false,
    [switch]$DryRun = $false,
    # For `logs`: default shows only problem pods. `-All` shows every pod's tail.
    [switch]$All = $false,

    # Worker toggles for `deploy`. Accept a comma-separated list of worker
    # short names from configs/openrelik-workers.yaml.
    # Example: deploy -Enable "grep,strings,plaso" -Disable "eztools,capa"
    [Parameter(Mandatory = $false)]
    [string]$Enable,
    [Parameter(Mandatory = $false)]
    [string]$Disable
)

# Color constants
$Colors = @{
    Header = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "White"
    Gray = "Gray"
    Command = "Magenta"
}

# Build the command path relative to the user's current directory
$ScriptCmd = (Resolve-Path -Relative $MyInvocation.MyCommand.Path) -replace '/', '\'

$script:IsFirstDeployment = $false

function Update-DeploymentContext {
    param(
        [string]$Namespace,
        [string]$ReleaseName
    )

    $tfStatePath = Join-Path $PSScriptRoot "..\terraform\terraform.tfstate"
    $hasTerraformState = Test-Path $tfStatePath

    $hasHelmRelease = $false
    try {
        $helmOutput = helm list -n $Namespace -o json 2>$null
        if ($helmOutput) {
            $helmReleases = $helmOutput | ConvertFrom-Json
            if ($helmReleases) {
                if ($helmReleases -isnot [System.Array]) {
                    $helmReleases = @($helmReleases)
                }
                $hasHelmRelease = ($helmReleases | Where-Object { $_.name -eq $ReleaseName } | Measure-Object).Count -gt 0
            }
        }
    } catch {
        $hasHelmRelease = $false
    }

    $script:IsFirstDeployment = -not ($hasTerraformState -or $hasHelmRelease)
}

function Get-HelmTimeoutSeconds {
    if ($script:IsFirstDeployment) {
        return 1500
    }
    return 600
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
    Write-Host "Usage: $ScriptCmd [action] [options]" -ForegroundColor $Colors.Warning
    Write-Host ""
    Write-Host "DEPLOYMENT + TEARDOWN:" -ForegroundColor $Colors.Success
    Write-Host "  deploy         - Full deployment (Docker + Minikube + Terraform + Services)"
    Write-Host "  shutdown-lab   - Clean shutdown via terraform destroy (preserves AI models & data)" -ForegroundColor $Colors.Header
    Write-Host "  destroy-lab    - Complete destruction (deletes Minikube cluster, AI models, data)" -ForegroundColor $Colors.Error
    Write-Host "  uninstall      - Helm-uninstall the release only (pods gone, Minikube + data stay)"
    Write-Host "  docker         - Ensure Docker Desktop is running and print its version"
    Write-Host ""
    Write-Host "STATUS + MONITORING:" -ForegroundColor $Colors.Success
    Write-Host "  status         - Show deployment + pod + port-forward summary"
    Write-Host "  minikube       - Show Minikube cluster + tunnel job status"
    Write-Host "  storage        - Show PV/PVC storage utilization"
    Write-Host "  jobs           - List background PowerShell jobs (tunnel + port-forwards)"
    Write-Host "  logs           - Show logs for problem pods (add -All for every pod)"
    Write-Host ""
    Write-Host "SERVICE ACCESS:" -ForegroundColor $Colors.Success
    Write-Host "  start          - Start port forwarding for all deployed UIs"
    Write-Host "  stop           - Stop port forwarding jobs (pods stay running in the cluster)"
    Write-Host "  restart        - Stop and re-start port forwarding jobs"
    Write-Host "  creds          - Show UI credentials (admin/admin) for deployed services"
    Write-Host ""
    Write-Host "AI + SPECIALIZED:" -ForegroundColor $Colors.Success
    Write-Host "  ollama         - Show Ollama pod + models, then run built-in prompt tests"
    Write-Host "  mcp-setup      - Configure/enable MCP server API keys and secrets"
    Write-Host ""
    Write-Host "OpenRelik workers are managed by a separate script. Examples:" -ForegroundColor $Colors.Gray
    Write-Host "  .\scripts\manage-openrelik-workers.ps1 list" -ForegroundColor $Colors.Command
    Write-Host "  .\scripts\manage-openrelik-workers.ps1 enable plaso" -ForegroundColor $Colors.Command
    Write-Host "  .\scripts\manage-openrelik-workers.ps1 disable hayabusa" -ForegroundColor $Colors.Command
    Write-Host ""
    Write-Host "Options:" -ForegroundColor $Colors.Header
    Write-Host "  -h                Show help (alias for 'help')"
    Write-Host "  -Service          Filter creds/logs by service (all, timesketch, openrelik, yeti)"
    Write-Host "  -All              (logs only) Include logs for healthy pods too"
    Write-Host "  -Force            Skip confirmation prompts on destructive actions"
    Write-Host "  -DryRun           Show what would happen without executing (deploy + cleanup)"
    Write-Host "  -Enable <names>   (deploy only) Comma-separated worker short names to enable"
    Write-Host "  -Disable <names>  (deploy only) Comma-separated worker short names to disable"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor $Colors.Header
    Write-Host "  $ScriptCmd -h"
    Write-Host "  $ScriptCmd deploy"
    Write-Host "  $ScriptCmd deploy -Enable `"grep,strings,plaso`" -Disable `"eztools`""
    Write-Host "  $ScriptCmd status"
    Write-Host "  $ScriptCmd creds"
    Write-Host "  $ScriptCmd creds -Service timesketch"
    Write-Host "  $ScriptCmd logs                          # problem pods only"
    Write-Host "  $ScriptCmd logs -All                     # every pod"
    Write-Host "  $ScriptCmd shutdown-lab                  # preserves AI models + data" -ForegroundColor $Colors.Header
    Write-Host "  $ScriptCmd destroy-lab                   # nuclear option - removes everything" -ForegroundColor $Colors.Error
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
    
    # Get CPU count and allocate 50%, minimum 2
    $totalCPUs = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    $cpus = [math]::Max([math]::Floor($totalCPUs * 0.5), 2)
    
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

function Start-OSDFIRMinikube {
    Show-Header "Starting OSDFIR Minikube Cluster"
    
    # Check if Minikube is already running with the osdfir profile
    $minikubeStatus = minikube status --profile=osdfir 2>&1
    
    if ($minikubeStatus -match "Running" -and $LASTEXITCODE -eq 0) {
        Write-Host "[INFO] Minikube 'osdfir' profile is already running" -ForegroundColor $Colors.Info
        Write-Host "Type: $(minikube profile)" -ForegroundColor $Colors.Info
        return $true
    }
    
    # Calculate system resources
    $totalMemory = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    $totalMemory = [math]::Round($totalMemory, 1)
    $totalCPUs = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
    
    # Get Docker memory allocation
    $dockerMemory = 0
    try {
        $dockerInfo = docker info --format "{{.MemTotal}}" 2>$null
        if ($dockerInfo) {
            $dockerMemory = [math]::Round(($dockerInfo / 1GB), 1)
        }
    } catch {
        $dockerMemory = "Unknown"
    }
    
    # Calculate Minikube resource allocation (50% of system CPUs, 60% of memory)
    $minikubeMemory = [math]::Min(12, [math]::Floor($totalMemory * 0.6))
    $minikubeCPUs = [math]::Max([math]::Floor($totalCPUs * 0.5), 2)
    
    Write-Host "System Resources:" -ForegroundColor $Colors.Info
    Write-Host "  Total Memory: ${totalMemory}GB" -ForegroundColor $Colors.Info
    Write-Host "  Total CPUs: $totalCPUs" -ForegroundColor $Colors.Info
    Write-Host "  Docker Memory: ${dockerMemory}GB" -ForegroundColor $Colors.Info
    Write-Host ""
    Write-Host "Minikube Allocation:" -ForegroundColor $Colors.Info
    Write-Host "  Memory: ${minikubeMemory}GB" -ForegroundColor $Colors.Info
    Write-Host "  CPUs: $minikubeCPUs" -ForegroundColor $Colors.Info
    Write-Host ""
    
    # Set NO_PROXY environment variable
    $noProxy = "localhost,127.0.0.1,10.96.0.0/12,192.168.59.0/24,192.168.49.0/24,192.168.39.0/24,registry.k8s.io"
    Write-Host "Using NO_PROXY: $noProxy" -ForegroundColor $Colors.Info
    
    # Start Minikube
    Write-Host "Starting Minikube with profile 'osdfir'..." -ForegroundColor $Colors.Info
    $minikubeCommand = "minikube start --profile=osdfir --driver=docker --memory=${minikubeMemory}GB --cpus=$minikubeCPUs --disk-size=40GB --kubernetes-version=stable --docker-env NO_PROXY=$noProxy --docker-env NO_PROXY=$noProxy"
    Write-Host "Running: $minikubeCommand" -ForegroundColor $Colors.Command
    
    Invoke-Expression $minikubeCommand
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "[OK] Minikube started successfully" -ForegroundColor $Colors.Success
        Write-Host ""
        return $true
    } else {
        Write-Host ""
        Write-Host "[ERROR] Failed to start Minikube" -ForegroundColor $Colors.Error
        Write-Host ""
        return $false
    }
}

function Start-MinikubeTunnel {
    Write-Host ""
    Write-Host "Checking Minikube tunnel..." -ForegroundColor $Colors.Info
    
    # Check if tunnel job already exists
    $existingJob = Get-Job -Name "minikube-tunnel" -ErrorAction SilentlyContinue
    if ($existingJob -and $existingJob.State -eq "Running") {
        # Check if LoadBalancer services have external IPs
        $lbServices = kubectl get services --all-namespaces --field-selector metadata.namespace=$Namespace --no-headers -o custom-columns=":metadata.name,:spec.type,:status.loadBalancer.ingress[0].ip" | 
                     Where-Object { $_ -match "LoadBalancer" }
        
        if ($lbServices -and $lbServices -match "\S+\s+LoadBalancer\s+\d+\.\d+\.\d+\.\d+") {
            Write-Host "[OK] Minikube tunnel is already running and working properly" -ForegroundColor $Colors.Success
            Write-Host "LoadBalancer services are accessible on localhost" -ForegroundColor $Colors.Info
            return
        }
        
        Write-Host "Existing tunnel job found but may not be working properly" -ForegroundColor $Colors.Warning
        Write-Host "Stopping existing tunnel job..." -ForegroundColor $Colors.Warning
        $existingJob | Stop-Job
        $existingJob | Remove-Job -Force
    } elseif ($existingJob) {
        Write-Host "Cleaning up non-running tunnel job..." -ForegroundColor $Colors.Warning
        $existingJob | Remove-Job -Force
    }
    
    # Start tunnel in background job
    Write-Host "Starting Minikube tunnel..." -ForegroundColor $Colors.Info
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
    Write-Host "Deleting OSDFIR Lab Minikube Cluster..." -ForegroundColor $Colors.Error
    Write-Host "=======================================" -ForegroundColor $Colors.Error
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
        
        Write-Host "Waiting for Docker Desktop to start..." -ForegroundColor $Colors.Info
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
        Write-Host "TIP: Run $ScriptCmd deploy to start the full environment" -ForegroundColor $Colors.Info
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
            "Running"   { "[RUNNING]" }
            "Completed" { "[STOPPED]" }
            "Stopped"   { "[STOPPED]" }
            "Failed"    { "[FAILED]" }
            default     { "[$($tunnelJob.State.ToString().ToUpper())]" }
        }
        $color = switch ($tunnelJob.State) {
            "Running" { $Colors.Success }
            "Failed"  { $Colors.Error }
            default   { $Colors.Warning }
        }
        Write-Host "  $status Minikube tunnel" -ForegroundColor $color
        if ($tunnelJob.State -ne "Running") {
            Write-Host "  (Minikube tunnel jobs can stop after OS sleep / Docker restart." -ForegroundColor $Colors.Gray
            Write-Host "   Run '$ScriptCmd start' to re-establish it.)" -ForegroundColor $Colors.Gray
        }
    } else {
        Write-Host "  [NOT RUNNING] Minikube tunnel" -ForegroundColor $Colors.Warning
        Write-Host "  Run '$ScriptCmd start' to start the tunnel." -ForegroundColor $Colors.Gray
    }
}

function Show-OllamaStatus {
    Show-Header "Ollama AI Status and Prompt Tests"

    if (-not (Test-KubectlAccess)) {
        return
    }

    # Check Ollama pod status
    Write-Host "Ollama Pod Status:" -ForegroundColor $Colors.Success
    $ollamaPod = kubectl get pods -n $Namespace -l app=ollama --no-headers 2>$null
    if (-not $ollamaPod) {
        Write-Host "  [ERROR] Ollama pod not found" -ForegroundColor $Colors.Error
        return
    }
    $parts  = $ollamaPod -split '\s+'
    $name   = $parts[0]
    $status = $parts[2]
    if ($status -eq "Running") {
        Write-Host "  [OK] $name" -ForegroundColor $Colors.Success
    } else {
        Write-Host "  [ERROR] $name ($status)" -ForegroundColor $Colors.Error
        return
    }

    # List available models
    Write-Host ""
    Write-Host "Available Models:" -ForegroundColor $Colors.Success
    $availableModels = @()
    $modelOutput = kubectl exec -n $Namespace $name -- ollama list 2>$null
    if ($modelOutput) {
        $modelLines = ($modelOutput -split "`n") | Where-Object { $_ -match "^\w+.*\d+\s+(GB|MB|KB)" }
        foreach ($line in $modelLines) {
            $p = $line -split '\s+'
            $availableModels += $p[0]
            Write-Host "  [OK] $($p[0]) (Size: $($p[2]) $($p[3]))" -ForegroundColor $Colors.Success
        }
    }
    if ($availableModels.Count -eq 0) {
        Write-Host "  [INFO] No models found" -ForegroundColor $Colors.Warning
        return
    }

    # Run the built-in prompt suite against the first model
    $testModel = $availableModels[0]
    Write-Host ""
    Write-Host "Testing model '$testModel' with sample prompts (a few moments each)..." -ForegroundColor $Colors.Info

    $testPrompts = @(
        "Name 3 common digital forensics file types in a single comma-separated line.",
        "Tell me a one-liner pun about digital forensics.",
        "Write a single haiku about finding deleted files."
    )

    $testNum = 0
    foreach ($prompt in $testPrompts) {
        $testNum++
        Write-Host ""
        Write-Host "Test ${testNum} of $($testPrompts.Count):" -ForegroundColor $Colors.Header
        Write-Host "  Prompt: $prompt" -ForegroundColor $Colors.Gray
        try {
            $escaped = $prompt -replace "'", "'\''"
            $result  = kubectl exec -n $Namespace $name -- sh -c "echo '$escaped' | ollama run $testModel 2>/dev/null" 2>$null
            $cleaned = $result -replace "\x1b\[[0-9;?]*[a-zA-Z]","" -replace "\x1b\[[0-9;?]*[hlK]","" -replace "`r","" | Where-Object { $_.Trim() -ne "" }
            $response = ($cleaned -join "`n").Trim()

            if ($response -and $response.Length -gt 0) {
                Write-Host "  Response:" -ForegroundColor $Colors.Success
                foreach ($line in $response -split "`n") {
                    Write-Host "    $line" -ForegroundColor $Colors.Gray
                }
            } else {
                Write-Host "  [ERROR] AI model not responding properly" -ForegroundColor $Colors.Error
            }
        } catch {
            Write-Host "  [WARNING] $($_.Exception.Message)" -ForegroundColor $Colors.Warning
        }
    }
    Write-Host ""
    Write-Host "Ollama checks complete." -ForegroundColor $Colors.Success
}

function Show-Status {
    Show-Header "OSDFIR Lab Deployment Status"
    
    # Check Minikube first
    if (-not (Test-MinikubeRunning)) {
        Write-Host "Minikube cluster 'osdfir' is not running" -ForegroundColor $Colors.Error
        Write-Host "TIP: Run $ScriptCmd deploy to start the full environment" -ForegroundColor $Colors.Info
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
        Write-Host "  TIP: Run $ScriptCmd start" -ForegroundColor $Colors.Info
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
    Show-Header "Starting OSDFIR Lab Services"
    
    # Check prerequisites
    if (-not (Test-MinikubeRunning)) {
        Write-Host "ERROR: Minikube cluster is not running" -ForegroundColor $Colors.Error
        Write-Host "TIP: Run $ScriptCmd deploy to start the full environment" -ForegroundColor $Colors.Info
        return
    }
    
    if (-not (Test-KubectlAccess)) {
        return
    }
    
    Write-Host "Discovering deployed services..." -ForegroundColor $Colors.Info

    $services = @(
        @{Name="Timesketch"; Service="$ReleaseName-timesketch"; Port="5000"},
        @{Name="OpenRelik-UI"; Service="$ReleaseName-openrelik-nginx"; Port="8711"},
        @{Name="OpenRelik-API"; Service="$ReleaseName-openrelik-nginx"; Port="8710"},
        @{Name="Yeti"; Service="$ReleaseName-yeti"; Port="9000"},
        @{Name="Timesketch-MCP"; Service="timesketch-mcp-server"; Port="8081"},
        @{Name="OpenRelik-MCP"; Service="openrelik-mcp-server"; Port="7070"},
        @{Name="Yeti-MCP"; Service="yeti-mcp-server"; Port="8082"}
    )

    $availableServices = @()
    foreach ($svc in $services) {
        $null = kubectl get service $svc.Service -n $Namespace --no-headers 2>$null
        if ($LASTEXITCODE -eq 0) {
            $availableServices += $svc
        }
    }
    
    if ($availableServices.Count -eq 0) {
        Write-Host "ERROR: No OSDFIR Lab services are available. Please check your deployment." -ForegroundColor $Colors.Error
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
    Write-Host "Port forwarding is now active!" -ForegroundColor $Colors.Success

    Write-Host ""
    Write-Host "OSDFIR Services Available:" -ForegroundColor $Colors.Success
    foreach ($svc in $availableServices) {
        Write-Host "  $($svc.Name): http://localhost:$($svc.Port)" -ForegroundColor $Colors.Header
    }
}

function Build-WorkerOverride {
    # Generate configs/osdfir-lab-workers.generated.yaml containing only the
    # openrelik.workers entries that are both enabled AND have a deployable
    # image. Terraform passes this file to helm_release AFTER osdfir-lab-values.yaml
    # so the workers array is replaced (Helm uses list-replace, not list-merge).
    # Net effect: Helm creates Deployments only for workers that are enabled AND
    # have an image; no-image entries stay purely informational.
    #
    # Returns $true on success.
    $valuesPath   = Join-Path $PSScriptRoot "..\configs\osdfir-lab-values.yaml"
    $overridePath = Join-Path $PSScriptRoot "..\configs\osdfir-lab-workers.generated.yaml"

    if (-not (Test-Path $valuesPath)) {
        Write-Host "ERROR: missing $valuesPath" -ForegroundColor $Colors.Error
        return $false
    }

    Import-Module powershell-yaml -ErrorAction Stop
    $values = Get-Content $valuesPath -Raw | ConvertFrom-Yaml

    $baseWorkers = @()
    if ($values.openrelik -and $values.openrelik.workers) {
        $baseWorkers = @($values.openrelik.workers)
    }

    # Helm template only needs the fields it templates over (name, image,
    # command, env, resources). Strip catalog metadata from the override so we
    # don't write entries the chart doesn't use.
    $chartFields = @('name','image','command','env','resources')
    $filtered = @()
    $skippedDisabled = 0
    $skippedNoImage  = 0
    foreach ($w in $baseWorkers) {
        if (-not $w.enabled) { $skippedDisabled++; continue }
        if (-not $w.image)   { $skippedNoImage++;  continue }
        $stripped = @{}
        foreach ($k in $chartFields) {
            if ($w.ContainsKey($k)) { $stripped[$k] = $w[$k] }
        }
        $filtered += $stripped
    }

    $override = @{
        openrelik = @{
            workers = $filtered
        }
    }
    $override | ConvertTo-Yaml | Set-Content $overridePath -Encoding UTF8

    Write-Host "Generated worker override: $($filtered.Count) enabled, $skippedDisabled disabled, $skippedNoImage no-image" -ForegroundColor $Colors.Info
    return $true
}

function Update-WorkerCatalog {
    # Apply -Enable / -Disable tokens from `deploy` to the openrelik.workers
    # entries in configs/osdfir-lab-values.yaml BEFORE helm runs. Tokens are
    # worker short names ("strings") or full names ("openrelik-worker-strings").
    # Returns $true if every token resolved.
    param(
        [string]$EnableTokens,
        [string]$DisableTokens
    )

    if (-not $EnableTokens -and -not $DisableTokens) { return $true }

    $valuesPath = Join-Path $PSScriptRoot "..\configs\osdfir-lab-values.yaml"
    if (-not (Test-Path $valuesPath)) {
        Write-Host "ERROR: values.yaml not found at $valuesPath" -ForegroundColor $Colors.Error
        return $false
    }

    Import-Module powershell-yaml -ErrorAction Stop
    $catalog = (Get-Content $valuesPath -Raw | ConvertFrom-Yaml).openrelik.workers

    # Local helpers (closures capture $catalog / $valuesPath)
    $resolveToken = {
        param([string]$Token)
        $t = $Token.Trim()
        if (-not $t) { return $null }
        $short = $t -replace '^openrelik-worker-', ''
        $match = $catalog | Where-Object { ($_.name -replace '^openrelik-worker-', '') -eq $short }
        if (-not $match) {
            Write-Host "  ERROR: worker '$t' not found in catalog" -ForegroundColor $Colors.Error
            return $null
        }
        if ($match.source -eq 'no-image') {
            Write-Host "  WARNING: '$short' has source:no-image; enabling it has no effect until you add image/command" -ForegroundColor $Colors.Warning
        }
        return $short
    }

    $applyToCatalog = {
        param([string]$ShortName, [string]$TargetState)
        $fullName = "openrelik-worker-$ShortName"
        $nameAlts = "(?:$([regex]::Escape($ShortName))|$([regex]::Escape($fullName)))"
        $lines = Get-Content $valuesPath
        $inTarget = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*-\s*name:\s*$nameAlts\s*$") { $inTarget = $true; continue }
            if ($inTarget -and $lines[$i] -match '^\s*-\s*name:') { break }
            if ($inTarget -and $lines[$i] -match '^\s*enabled:\s*(true|false)') {
                $lines[$i] = $lines[$i] -replace 'enabled:\s*(true|false)', "enabled: $TargetState"
                break
            }
        }
        $lines | Set-Content $valuesPath -Encoding UTF8
    }

    $allOk = $true

    if ($EnableTokens) {
        Write-Host "Applying -Enable to worker catalog..." -ForegroundColor $Colors.Info
        foreach ($tok in ($EnableTokens -split ',')) {
            $name = & $resolveToken $tok
            if ($name) {
                & $applyToCatalog $name 'true'
                Write-Host "  enabled: $name" -ForegroundColor $Colors.Success
            } else {
                $allOk = $false
            }
        }
    }

    if ($DisableTokens) {
        Write-Host "Applying -Disable to worker catalog..." -ForegroundColor $Colors.Info
        foreach ($tok in ($DisableTokens -split ',')) {
            $name = & $resolveToken $tok
            if ($name) {
                & $applyToCatalog $name 'false'
                Write-Host "  disabled: $name" -ForegroundColor $Colors.Success
            } else {
                $allOk = $false
            }
        }
    }

    return $allOk
}

function Invoke-HelmPull {
    # Pre-pull the osdfir-infrastructure chart tarball into terraform/chart-cache/
    # so the terraform helm provider can resolve it at plan time. Reads the chart
    # version from terraform/variables.tf so there's a single source of truth.
    # Returns $true on success, $false otherwise.
    $varsPath = Join-Path $PSScriptRoot "..\terraform\variables.tf"
    if (-not (Test-Path $varsPath)) {
        Write-Host "ERROR: Could not find $varsPath" -ForegroundColor $Colors.Error
        return $false
    }

    $match = Select-String -Path $varsPath -Pattern 'default\s*=\s*"(\d+\.\d+\.\d+)"' | Select-Object -First 1
    if (-not $match) {
        Write-Host "ERROR: Could not parse osdfir_chart_version from $varsPath" -ForegroundColor $Colors.Error
        return $false
    }
    $chartVersion = $match.Matches[0].Groups[1].Value

    $cacheDir = Join-Path $PSScriptRoot "..\terraform\chart-cache"
    $tarball  = Join-Path $cacheDir "osdfir-infrastructure-$chartVersion.tgz"

    if (Test-Path $tarball) {
        Write-Host "Chart $chartVersion already cached at $tarball" -ForegroundColor $Colors.Info
        return $true
    }

    Write-Host "Pulling osdfir-infrastructure chart $chartVersion..." -ForegroundColor $Colors.Info
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

    helm pull osdfir-infrastructure `
        --repo https://google.github.io/osdfir-infrastructure/ `
        --version $chartVersion `
        --destination $cacheDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: helm pull failed (exit $LASTEXITCODE)" -ForegroundColor $Colors.Error
        return $false
    }

    if (-not (Test-Path $tarball)) {
        Write-Host "ERROR: helm pull succeeded but tarball not found at $tarball" -ForegroundColor $Colors.Error
        return $false
    }

    Write-Host "Chart cached: $tarball" -ForegroundColor $Colors.Success
    return $true
}

function Set-OpenRelikAdmin {
    # Creates an OpenRelik admin user using admin.py inside the openrelik-server
    # container (https://github.com/openrelik/openrelik-deploy/blob/main/docker/install.sh).
    # Idempotent: admin.py prints "created/updated" on subsequent runs.
    Show-Header "Configuring OpenRelik admin/admin login"

    $deploy  = "$ReleaseName-openrelik-api"
    $podLine = kubectl get pods -n $Namespace --no-headers 2>$null |
        Where-Object { $_ -match "^$([regex]::Escape($deploy))-\S+\s+\d/\d\s+Running" } |
        Select-Object -First 1

    if (-not $podLine) {
        Write-Host "WARNING: No running openrelik-api pod found. Skipping admin user setup." -ForegroundColor $Colors.Warning
        Write-Host "Create the admin user manually once pods are ready:" -ForegroundColor $Colors.Info
        Write-Host "  kubectl exec -n $Namespace deploy/$deploy -- python admin.py create-user admin --password admin --admin" -ForegroundColor $Colors.Gray
        return
    }

    $podName = ($podLine -split '\s+')[0]
    Write-Host "Using pod: $podName" -ForegroundColor $Colors.Info

    $output = kubectl exec -n $Namespace $podName -- python admin.py create-user admin --password admin --admin 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OpenRelik user 'admin' created or updated (password: admin)." -ForegroundColor $Colors.Success
    } else {
        Write-Host "WARNING: admin.py create-user did not succeed. Output:" -ForegroundColor $Colors.Warning
        Write-Host $output.Trim() -ForegroundColor $Colors.Gray
    }
}

function Set-TimesketchAdmin {
    # Creates (or no-ops on) a Timesketch user 'admin' with password 'admin'.
    # Runs post-deploy - more reliable than relying on Helm lookup() for secret pre-seeding.
    Show-Header "Configuring Timesketch admin/admin login"

    # Find a running Timesketch pod. Try the known deployment name first, then fall back to label match.
    $podLine = kubectl get pods -n $Namespace --no-headers 2>$null |
        Where-Object { $_ -match "^$([regex]::Escape($ReleaseName))-timesketch-\S+\s+\d/\d\s+Running" } |
        Where-Object { $_ -notmatch '-worker|-postgres|-redis|-opensearch' } |
        Select-Object -First 1

    if (-not $podLine) {
        Write-Host "WARNING: No running Timesketch pod found. Skipping admin user setup." -ForegroundColor $Colors.Warning
        Write-Host "Create the admin user manually once pods are ready:" -ForegroundColor $Colors.Info
        Write-Host "  kubectl exec -n $Namespace deploy/$ReleaseName-timesketch -- tsctl add_user -u admin -p admin" -ForegroundColor $Colors.Gray
        return
    }

    $podName = ($podLine -split '\s+')[0]
    Write-Host "Using pod: $podName" -ForegroundColor $Colors.Info

    # Timesketch's tsctl uses `create-user` (idempotent: prints "created/updated").
    # `add_user` exists only in older versions.
    $output = kubectl exec -n $Namespace $podName -- tsctl create-user admin --password admin 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Timesketch user 'admin' created or updated (password: admin)." -ForegroundColor $Colors.Success
    } else {
        Write-Host "WARNING: tsctl create-user did not succeed. Output:" -ForegroundColor $Colors.Warning
        Write-Host $output.Trim() -ForegroundColor $Colors.Gray
    }
}

function Get-DeployedUIs {
    # Returns the subset of UI services that are actually deployed in the
    # cluster right now. Used by the deploy final output and Show-Credentials.
    #
    # NoCreds=true entries appear in service-URL listings but are filtered
    # out of the creds view because they don't use admin/admin (e.g. the
    # OpenSearch Dashboard inherits OpenSearch's own auth).
    $candidates = @(
        [PSCustomObject]@{ Name = "Timesketch";           Service = "$ReleaseName-timesketch";             Url = "http://localhost:5000";             NoCreds = $false }
        [PSCustomObject]@{ Name = "OpenRelik";            Service = "$ReleaseName-openrelik-nginx";        Url = "http://localhost:8711";             NoCreds = $false }
        [PSCustomObject]@{ Name = "OpenRelik API";        Service = "$ReleaseName-openrelik-nginx";        Url = "http://localhost:8710";             NoCreds = $false }
        [PSCustomObject]@{ Name = "Yeti";                 Service = "$ReleaseName-yeti";                   Url = "http://localhost:9000";             NoCreds = $false }
        # OpenSearch Dashboard is served through Timesketch's nginx at /opensearch
        # when opensearch.dashboard.ingress is true. The dashboard Deployment
        # (and its own Service) only exist when opensearch.selfSigned is true.
        [PSCustomObject]@{ Name = "OpenSearch Dashboard"; Service = "$ReleaseName-opensearch-dashboard";   Url = "http://localhost:5000/opensearch";  NoCreds = $true }
    )
    $available = @()
    foreach ($c in $candidates) {
        $null = kubectl get service $c.Service -n $Namespace --no-headers 2>$null
        if ($LASTEXITCODE -eq 0) { $available += $c }
    }
    return $available
}

function Show-ServiceCredential {
    param($ServiceName, $ServiceUrl)

    Write-Host "$ServiceName Credentials:" -ForegroundColor $Colors.Header
    Write-Host "  Service URL: $ServiceUrl" -ForegroundColor $Colors.Success
    Write-Host "  Username:    admin" -ForegroundColor $Colors.Success
    Write-Host "  Password:    admin" -ForegroundColor $Colors.Success
    Write-Host ""
}

function Show-Credentials {
    # Prints static admin/admin credentials only for UIs whose Kubernetes
    # Service is present in the namespace. Respects -Service filter.
    Show-Header "OSDFIR Lab Service Credentials"

    Write-Host "Static admin/admin credentials (test lab - see README disclaimer)." -ForegroundColor $Colors.Info
    Write-Host ""

    if (-not (Test-KubectlAccess)) { return }

    $deployed = Get-DeployedUIs
    # Skip:
    #  - OpenRelik API (same login as the UI, not a separate endpoint)
    #  - Anything NoCreds (e.g. OpenSearch Dashboard inherits OpenSearch's own auth)
    $deployed = $deployed | Where-Object { $_.Name -ne "OpenRelik API" -and -not $_.NoCreds }

    if ($Service -ne "all") {
        $deployed = $deployed | Where-Object { $_.Name -match "^$Service$" -or $_.Name -match "^$Service\b" -or $_.Name.ToLower().StartsWith($Service.ToLower()) }
    }

    if (-not $deployed -or $deployed.Count -eq 0) {
        Write-Host "No matching UI services are deployed in namespace '$Namespace'." -ForegroundColor $Colors.Warning
        return
    }

    foreach ($ui in $deployed) {
        Show-ServiceCredential -ServiceName $ui.Name -ServiceUrl $ui.Url
    }

    Write-Host "NOTE: These are static lab credentials. Do not use this deployment in production." -ForegroundColor $Colors.Warning
}

function Setup-McpServers {
    Show-Header "MCP Server Setup"

    if (-not (Test-KubectlAccess)) {
        return
    }

    # Define MCP servers and their secret requirements
    # Timesketch MCP uses the existing Timesketch secret - no extra setup needed
    $mcpServers = @(
        @{
            Name        = "Timesketch MCP"
            Service     = "timesketch-mcp-server"
            SecretName  = ""  # Uses existing timesketch secret
            SecretKey   = ""
            SetupNote   = ""
        },
        @{
            Name        = "OpenRelik MCP"
            Service     = "openrelik-mcp-server"
            SecretName  = "openrelik-mcp-secret"
            SecretKey   = "api-key"
            SetupNote   = "Create an API key in OpenRelik UI: Log in > Settings > API Keys > Create"
        },
        @{
            Name        = "Yeti MCP"
            Service     = "yeti-mcp-server"
            SecretName  = "yeti-mcp-secret"
            SecretKey   = "api-key"
            SetupNote   = "Create an API key in Yeti UI: Log in > Admin > API Keys > Create"
        }
    )

    $foundAny = $false

    foreach ($mcp in $mcpServers) {
        # Check if this MCP server is deployed
        $svc = kubectl get service $mcp.Service -n $Namespace --no-headers 2>$null
        if ($LASTEXITCODE -ne 0) {
            continue
        }

        $foundAny = $true
        Write-Host "$($mcp.Name):" -ForegroundColor $Colors.Header

        # Check pod status
        $pod = kubectl get pods -n $Namespace -l "app=$($mcp.Service)" --no-headers 2>$null
        if ($pod) {
            $parts = $pod -split '\s+'
            $podStatus = $parts[2]
            if ($podStatus -eq "Running") {
                Write-Host "  [OK] Pod is running" -ForegroundColor $Colors.Success
            } else {
                Write-Host "  [WARN] Pod status: $podStatus" -ForegroundColor $Colors.Warning
            }
        } else {
            Write-Host "  [ERROR] No pod found" -ForegroundColor $Colors.Error
        }

        # If no secret needed (Timesketch), just report status
        if (-not $mcp.SecretName) {
            Write-Host "  [OK] Uses existing Timesketch credentials (no extra setup needed)" -ForegroundColor $Colors.Success
            Write-Host ""
            continue
        }

        # Check if the secret already exists
        $existingSecret = kubectl get secret $mcp.SecretName -n $Namespace --no-headers 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Secret '$($mcp.SecretName)' exists" -ForegroundColor $Colors.Success
            Write-Host ""
            continue
        }

        # Secret doesn't exist - guide the user
        Write-Host "  [MISSING] Secret '$($mcp.SecretName)' not found" -ForegroundColor $Colors.Warning
        Write-Host "  $($mcp.SetupNote)" -ForegroundColor $Colors.Info
        Write-Host ""

        $apiKey = Read-Host "  Enter $($mcp.Name) API key (or press Enter to skip)" -MaskInput
        if ($apiKey -and $apiKey.Trim().Length -gt 0) {
            kubectl create secret generic $mcp.SecretName --from-literal="$($mcp.SecretKey)=$($apiKey.Trim())" -n $Namespace 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Secret '$($mcp.SecretName)' created" -ForegroundColor $Colors.Success
                # Restart the MCP pod so it picks up the new secret
                kubectl rollout restart deployment/$mcp.Service -n $Namespace 2>$null
                Write-Host "  [OK] Restarting $($mcp.Name) pod..." -ForegroundColor $Colors.Success
            } else {
                Write-Host "  [ERROR] Failed to create secret" -ForegroundColor $Colors.Error
            }
        } else {
            Write-Host "  [SKIPPED] You can run $ScriptCmd mcp-setup again later" -ForegroundColor $Colors.Warning
        }
        Write-Host ""
    }

    if (-not $foundAny) {
        Write-Host "No MCP servers are currently deployed." -ForegroundColor $Colors.Warning
        Write-Host ""
        Write-Host "To enable one or more MCP servers, set the matching variable(s) to true" -ForegroundColor $Colors.Info
        Write-Host "in terraform/variables.tf, then redeploy:" -ForegroundColor $Colors.Info
        Write-Host "  deploy_timesketch_mcp = true   (no extra secret required)" -ForegroundColor $Colors.Gray
        Write-Host "  deploy_openrelik_mcp  = true   (API key required - Settings > API Keys)" -ForegroundColor $Colors.Gray
        Write-Host "  deploy_yeti_mcp       = true   (API key required - Admin > API Keys)" -ForegroundColor $Colors.Gray
        Write-Host ""
        Write-Host "Then run:" -ForegroundColor $Colors.Info
        Write-Host "  $ScriptCmd deploy" -ForegroundColor $Colors.Command
        Write-Host ""
        Write-Host "After the MCP pods are running, run '$ScriptCmd mcp-setup' again" -ForegroundColor $Colors.Info
        Write-Host "to supply the API keys for OpenRelik / Yeti MCP." -ForegroundColor $Colors.Info
        return
    }

    Write-Host "MCP Server Endpoints:" -ForegroundColor $Colors.Header
    $endpoints = @(
        @{Name="Timesketch MCP"; Service="timesketch-mcp-server"; Port="8081"},
        @{Name="OpenRelik MCP"; Service="openrelik-mcp-server"; Port="7070"},
        @{Name="Yeti MCP"; Service="yeti-mcp-server"; Port="8082"}
    )
    foreach ($ep in $endpoints) {
        $svc = kubectl get service $ep.Service -n $Namespace --no-headers 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  $($ep.Name): http://$($ep.Service).$Namespace.svc.cluster.local:$($ep.Port)" -ForegroundColor $Colors.Success
        }
    }
    Write-Host ""
    Write-Host "TIP: Use these internal URLs when configuring MCP clients (e.g., Claude Desktop, VS Code)." -ForegroundColor $Colors.Info
}

function Show-PodLogs {
    param([string]$PodName, [string]$Ready, [string]$Status)

    Write-Host "$PodName ($Status)" -ForegroundColor $Colors.Info
    Write-Host "  ------------------------" -ForegroundColor $Colors.Gray

    if ($Status -match 'Running|Completed') {
        $logs = kubectl logs $PodName -n $Namespace --tail=10 2>&1
        if ($logs) {
            $logs | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "  (no log output)" -ForegroundColor $Colors.Gray
        }
    } elseif ($Status -match 'Init') {
        Write-Host "  Pod is initializing ($Ready init containers ready)" -ForegroundColor $Colors.Warning
    } elseif ($Status -match 'Creating|Pending') {
        Write-Host "  Pod is starting up" -ForegroundColor $Colors.Warning
    } elseif ($Status -match 'Error|BackOff|CrashLoop|ConfigError') {
        Write-Host "  Pod is in $Status state" -ForegroundColor $Colors.Error
        $events = kubectl get events -n $Namespace --field-selector "involvedObject.name=$PodName" --sort-by='.lastTimestamp' 2>$null | Select-Object -Last 3
        if ($events) { $events | ForEach-Object { Write-Host "  $_" -ForegroundColor $Colors.Gray } }
    } else {
        Write-Host "  Pod is in $Status state" -ForegroundColor $Colors.Warning
    }
    Write-Host ""
}

function Show-Logs {
    # Default: show logs only for pods in a problem state (CrashLoopBackOff,
    # Error, ConfigError, ErrImagePull, etc.). With -All, also show recent log
    # tails for every healthy pod.
    Show-Header "OSDFIR Lab Service Logs"
    if (-not (Test-KubectlAccess)) { return }

    $allPods = @(kubectl get pods -n $Namespace --no-headers 2>$null)
    if ($allPods.Count -eq 0) {
        Write-Host "No pods found in namespace '$Namespace'." -ForegroundColor $Colors.Warning
        return
    }

    # Filter by -Service parameter
    $prefix = [regex]::Escape($ReleaseName)
    $filter = switch ($Service) {
        "timesketch" { "^($prefix-timesketch|$prefix-opensearch)" }
        "openrelik"  { "^$prefix-openrelik" }
        "yeti"       { "^$prefix-yeti" }
        default      { "." }  # all
    }

    $filtered = @($allPods | Where-Object { $_ -match $filter })
    if ($Service -eq "all") { $filtered = $allPods }

    if ($filtered.Count -eq 0) {
        Write-Host "No pods found for service '$Service'." -ForegroundColor $Colors.Warning
        return
    }

    # Partition into problem vs healthy
    $errorPods   = @()
    $runningPods = @()
    foreach ($line in $filtered) {
        $status = ($line -split '\s+')[2]
        if ($status -match 'Error|BackOff|CrashLoop|ConfigError|ErrImage') {
            $errorPods += $line
        } else {
            $runningPods += $line
        }
    }

    if ($errorPods.Count -eq 0) {
        Write-Host "No problem pods." -ForegroundColor $Colors.Success
    } else {
        Write-Host "PROBLEM PODS ($($errorPods.Count)):" -ForegroundColor $Colors.Error
        Write-Host ""
        foreach ($line in $errorPods) {
            $fields = $line -split '\s+'
            Show-PodLogs -PodName $fields[0] -Ready $fields[1] -Status $fields[2]
        }
    }

    if (-not $All) {
        Write-Host ""
        Write-Host "$($runningPods.Count) healthy pod(s) not shown. Use '-All' to include them." -ForegroundColor $Colors.Gray
        return
    }

    Write-Host ""
    Write-Host "ALL PODS ($($runningPods.Count) healthy, $($errorPods.Count) problem):" -ForegroundColor $Colors.Success
    Write-Host ""
    foreach ($line in $runningPods) {
        $fields = $line -split '\s+'
        Show-PodLogs -PodName $fields[0] -Ready $fields[1] -Status $fields[2]
    }
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
    Show-Header "Full OSDFIR Lab Deployment"

    if (-not (Test-Prerequisites)) {
        return
    }

    # Resolve -Enable / -Disable worker toggles before anything else so bad
    # tokens fail fast without starting Docker / Minikube.
    if ($Enable -or $Disable) {
        if (-not (Update-WorkerCatalog -EnableTokens $Enable -DisableTokens $Disable)) {
            Write-Host "ERROR: One or more worker tokens could not be resolved. Aborting." -ForegroundColor $Colors.Error
            Write-Host "Run '.\scripts\manage-openrelik-workers.ps1 list' to see valid names and numbers." -ForegroundColor $Colors.Warning
            return
        }
    }

    Update-DeploymentContext -Namespace $Namespace -ReleaseName $ReleaseName
    if ($script:IsFirstDeployment) {
        Write-Host ""
        Write-Host "First-time deployment detected. Initial container pulls (especially the Ollama model download) can take longer than usual." -ForegroundColor $Colors.Warning
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
    if (-not (Start-OSDFIRMinikube)) {
        Write-Host "ERROR: Failed to start Minikube" -ForegroundColor $Colors.Error
        return
    }
    
    # Start tunnel after successful cluster start
    Start-MinikubeTunnel
    
     # Step 2.5: Build the MCP Server image
    #if (-not (New-MCPServerImage)) {
    #    Write-Host "ERROR: MCP Server image build failed. Halting deployment." -ForegroundColor $Colors.Error
    #    return
    #}
    
    # Step 3: Deploy with Terraform
    Write-Host ""
    Write-Host "Step 3: Deploying OSDFIR Lab with Terraform..." -ForegroundColor $Colors.Info

    # The terraform helm provider validates chart file paths at PLAN time, so we
    # pull the chart tarball before invoking terraform. Idempotent: re-pulls only
    # if the version-matching .tgz isn't already on disk.
    if (-not (Invoke-HelmPull)) {
        Write-Host "ERROR: Failed to pull the osdfir-infrastructure chart" -ForegroundColor $Colors.Error
        return
    }

    # Filter the openrelik.workers list down to just the catalog-enabled set.
    # Without this, Helm creates a Deployment for every worker in values.yaml
    # and Minikube spends minutes spinning up pods we're about to scale to 0.
    if (-not (Build-WorkerOverride)) {
        Write-Host "ERROR: Failed to generate the worker override values file" -ForegroundColor $Colors.Error
        return
    }

    Push-Location "$PSScriptRoot\..\terraform"
    try {
        $helmTimeoutSec = Get-HelmTimeoutSeconds
        terraform init
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Terraform init failed" -ForegroundColor $Colors.Error
            return
        }
        
        # Add after line 922 (terraform init)
        # Check for existing resources and import them into state if needed
        $existingResources = kubectl get deployment,service,configmap -n $Namespace -o json | ConvertFrom-Json
        foreach ($resource in $existingResources.items) {
            # Logic to import resources into Terraform state
        }

        # Check if Helm release exists and import it if needed
        Write-Host "Checking for existing Helm release..." -ForegroundColor $Colors.Info
        $existingRelease = helm list -n $Namespace -o json | ConvertFrom-Json | Where-Object { $_.name -eq $ReleaseName }
        if ($existingRelease) {
            Write-Host "Found existing release '$ReleaseName', importing into Terraform state..." -ForegroundColor $Colors.Warning
            terraform import helm_release.osdfir "$Namespace/$ReleaseName" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Successfully imported existing Helm release" -ForegroundColor $Colors.Success
            } else {
                Write-Host "Note: Import returned non-zero code, but this is often expected if already in state" -ForegroundColor $Colors.Info
            }
        }
        
        terraform apply -auto-approve -var "helm_timeout=$helmTimeoutSec"
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
    $timeout = Get-HelmTimeoutSeconds
    $elapsed = 0
    do {
        Start-Sleep -Seconds 20
        $elapsed += 20
        if ($elapsed -gt 0 -and ($elapsed % 120 -eq 0)) {
            Write-Host "Tip: Run 'kubectl get deploy -n $Namespace' in another terminal to monitor rollout progress." -ForegroundColor $Colors.Info
        }
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
        Write-Host ""
        Write-Host "WARNING: $runningPods/$totalPods pods ready after $timeout seconds. Some pods are still starting." -ForegroundColor $Colors.Warning
        Write-Host 'This is normal - image pulls and model downloads can take several minutes.' -ForegroundColor $Colors.Info
        Write-Host ""
        # Show which pods are not ready
        $notReady = $pods | Where-Object { $_ -notmatch "Running\s+.*/.*\s" -or $_ -match "0/" }
        if ($notReady) {
            Write-Host "Pods not yet ready:" -ForegroundColor $Colors.Warning
            $notReady | ForEach-Object {
                $parts = ($_ -split '\s+')
                $name = $parts[0]
                $ready = $parts[1]
                $status = $parts[2]
                Write-Host "  - $name ($status, $ready)" -ForegroundColor $Colors.Warning
            }
        }
        Write-Host ""
        Write-Host "Monitor pods until all are running:" -ForegroundColor $Colors.Info
        Write-Host "  kubectl get pods -n $Namespace -w" -ForegroundColor $Colors.Gray
        Write-Host "Check status anytime:" -ForegroundColor $Colors.Info
        Write-Host "  $ScriptCmd status" -ForegroundColor $Colors.Gray
        Write-Host "View logs for a failing pod:" -ForegroundColor $Colors.Info
        Write-Host ('  kubectl logs -n ' + $Namespace + ' <pod-name> --tail=30') -ForegroundColor $Colors.Gray
    } else {
        Write-Host "All $totalPods pods are ready!" -ForegroundColor $Colors.Success
    }

    # Step 5: Start services
    Write-Host ""
    Write-Host "Step 5: Starting port forwarding..." -ForegroundColor $Colors.Info
    Start-Services

    # Step 6: Configure admin/admin UI users (Timesketch + OpenRelik). Both are
    # idempotent: re-running updates the password instead of failing.
    Write-Host ""
    Write-Host "Step 6: Configuring Timesketch admin user..." -ForegroundColor $Colors.Info
    Set-TimesketchAdmin

    Write-Host ""
    Write-Host "Step 6b: Configuring OpenRelik admin user..." -ForegroundColor $Colors.Info
    Set-OpenRelikAdmin

    # Step 7: Reconcile OpenRelik workers to the catalog. Helm creates every
    # worker Deployment with 1 replica by default; apply scales the disabled
    # ones to 0 so the running set matches configs/openrelik-workers.yaml.
    #
    # There's a race: helm_release returns after submitting manifests but the
    # API server may still be creating Deployments. Wait briefly for
    # openrelik-api (the "ready signal" the manager script looks for) before
    # running apply, so the reconcile doesn't silently bail.
    Write-Host ""
    Write-Host "Step 7: Reconciling OpenRelik workers to catalog..." -ForegroundColor $Colors.Info
    $workerScript = Join-Path $PSScriptRoot "manage-openrelik-workers.ps1"
    if (-not (Test-Path $workerScript)) {
        Write-Host "WARNING: manage-openrelik-workers.ps1 not found; skipping worker reconcile." -ForegroundColor $Colors.Warning
    } else {
        $apiDeploy = "$ReleaseName-openrelik-api"
        $waited = 0
        $maxWait = 60
        while ($waited -lt $maxWait) {
            kubectl get deployment $apiDeploy -n $Namespace 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Seconds 3
            $waited += 3
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Deployment '$apiDeploy' did not appear within ${maxWait}s." -ForegroundColor $Colors.Warning
            Write-Host "Run '.\scripts\manage-openrelik-workers.ps1 apply' manually once pods are ready." -ForegroundColor $Colors.Gray
        } else {
            & $workerScript apply -Namespace $Namespace -ReleaseName $ReleaseName
        }
    }

    Write-Host ""
    Write-Host "Deployment completed!" -ForegroundColor $Colors.Success
    Write-Host ""
    Write-Host "Service URLs:" -ForegroundColor $Colors.Header
    $deployedUIs = Get-DeployedUIs
    if ($deployedUIs -and $deployedUIs.Count -gt 0) {
        $pad = ($deployedUIs | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum + 1
        foreach ($ui in $deployedUIs) {
            Write-Host ("  {0,-${pad}} {1}" -f ($ui.Name + ':'), $ui.Url) -ForegroundColor $Colors.Success
        }
    } else {
        Write-Host "  (none detected - check pod status)" -ForegroundColor $Colors.Warning
    }
    Write-Host ""
    Write-Host "Login (static lab credentials):" -ForegroundColor $Colors.Header
    Write-Host "  Username: admin" -ForegroundColor $Colors.Success
    Write-Host "  Password: admin" -ForegroundColor $Colors.Success
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor $Colors.Header

    # Build (command, description) pairs and align descriptions to a single column.
    $steps = @(
        @{ Cmd = "$ScriptCmd creds";                                Desc = "Show login credentials" }
        @{ Cmd = "$ScriptCmd logs";                                 Desc = "Show service logs and problem pods" }
        @{ Cmd = "$ScriptCmd ollama";                               Desc = "Check AI model status" }
        @{ Cmd = ".\scripts\manage-openrelik-workers.ps1 list";     Desc = "Enable/disable OpenRelik workers" }
    )

    # Check if any MCP servers are deployed and remind about setup
    $mcpServices = @("timesketch-mcp-server", "openrelik-mcp-server", "yeti-mcp-server")
    $hasMcp = $false
    foreach ($mcp in $mcpServices) {
        $null = kubectl get service $mcp -n $Namespace --no-headers 2>$null
        if ($LASTEXITCODE -eq 0) { $hasMcp = $true; break }
    }
    if ($hasMcp) {
        $steps += @{ Cmd = "$ScriptCmd mcp-setup"; Desc = "Configure MCP server API keys" }
    }

    # Pad the command column to the longest command + 2 spaces
    $padWidth = ($steps | ForEach-Object { $_.Cmd.Length } | Measure-Object -Maximum).Maximum + 2
    foreach ($s in $steps) {
        Write-Host -NoNewline "  " -ForegroundColor $Colors.Info
        Write-Host -NoNewline ($s.Cmd.PadRight($padWidth)) -ForegroundColor $Colors.Command
        Write-Host $s.Desc -ForegroundColor $Colors.Info
    }
    Write-Host ""
}

function Start-SmartCleanup {
    Show-Header 'Clean OSDFIR Lab Shutdown (Preserves AI Models & Data)'
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute the following steps:" -ForegroundColor $Colors.Warning
        Write-Host "1. Stop all port forwarding jobs" -ForegroundColor $Colors.Info
        Write-Host "2. Destroy Terraform resources" -ForegroundColor $Colors.Info
        Write-Host "3. Preserve Minikube cluster and persistent data" -ForegroundColor $Colors.Header
        return
    }
    
    if (-not $Force) {
        Write-Host "This will clean up OSDFIR Lab services but preserve:" -ForegroundColor $Colors.Info
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
    Write-Host '[OK] Services removed' -ForegroundColor $Colors.Success
    Write-Host '[OK] AI models preserved (next deploy will be faster)' -ForegroundColor $Colors.Header
    Write-Host '[OK] Database data preserved' -ForegroundColor $Colors.Header
    Write-Host '[OK] Minikube cluster ready for redeployment' -ForegroundColor $Colors.Header
}

function Start-FullCleanup {
    Show-Header "COMPLETE OSDFIR Lab Destruction (Nuclear Option)"
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute the following steps:" -ForegroundColor $Colors.Error
        Write-Host "1. Stop all port forwarding jobs" -ForegroundColor $Colors.Info
        Write-Host "2. Force-delete all Kubernetes resources and remove Terraform state" -ForegroundColor $Colors.Info
        Write-Host '3. Delete entire Minikube cluster (including AI models & data)' -ForegroundColor $Colors.Error
        return
    }
    
    Write-Host ""
    Write-Host "WARNING: COMPLETE DESTRUCTION MODE" -ForegroundColor $Colors.Error -BackgroundColor Black
    Write-Host ""
    Write-Host "This will permanently destroy:" -ForegroundColor $Colors.Error
    Write-Host "  - All OSDFIR Lab services" -ForegroundColor $Colors.Warning
    Write-Host "  - All database data" -ForegroundColor $Colors.Warning  
    Write-Host '  - All AI models (1.6GB+ will need re-download)' -ForegroundColor $Colors.Warning
    Write-Host "  - Entire Minikube cluster" -ForegroundColor $Colors.Warning
    Write-Host "  - All persistent volumes and data" -ForegroundColor $Colors.Warning
    Write-Host ""
    Write-Host "TIP: Consider 'shutdown-lab' instead to preserve AI models and data" -ForegroundColor $Colors.Info
    Write-Host ""
    
    if (-not $Force) {
        $confirmation = Read-Host "Type 'DESTROY' in all caps to confirm complete destruction"
        if ($confirmation -ne "DESTROY") {
            Write-Host "Complete destruction cancelled." -ForegroundColor $Colors.Success
            Write-Host "TIP: Use 'shutdown-lab' for smart cleanup that preserves data" -ForegroundColor $Colors.Info
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
    
    # Step 2: Clear Terraform state. The previous implementation also ran
    # `kubectl delete all --all --force --grace-period=0 ...` against the
    # namespace, but that can hang indefinitely waiting on pod/PVC finalizers.
    # It's also redundant: Step 3 deletes the entire Minikube cluster, which
    # wipes every k8s resource regardless. So we just clear local state here.
    Write-Host ""
    Write-Host "Step 2: Clearing Terraform state..." -ForegroundColor $Colors.Info
    $tfDir = Join-Path $PSScriptRoot "..\terraform"
    Remove-Item -Path (Join-Path $tfDir "terraform.tfstate")        -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $tfDir "terraform.tfstate.backup") -Force -ErrorAction SilentlyContinue
    Write-Host "  Terraform state cleared." -ForegroundColor $Colors.Success

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

#function New-MCPServerImage {
#    Show-Header "Building Timesketch MCP Server Image in Minikube"
    
#    $buildScriptPath = "$PSScriptRoot\build-timesketch-mcp.ps1"
    
#    if (-not (Test-Path $buildScriptPath)) {
#        Write-Host "ERROR: Build script not found at: $buildScriptPath" -ForegroundColor $Colors.Error
#        return $false
#    }
    
#    Write-Host "Executing build script with -Minikube and -Force flags..." -ForegroundColor $Colors.Info
#    Write-Host "This will build the image directly into Minikube's Docker daemon." -ForegroundColor $Colors.Warning
    
#    try {
#        # Execute the script and pass parameters, including the new switch.
#        & $buildScriptPath -Minikube -Force -CalledByManager
        
#        if ($LASTEXITCODE -eq 0) {
#            Write-Host "[OK] MCP Server image built successfully into Minikube" -ForegroundColor $Colors.Success
#            return $true
#        } else {
#            Write-Host "[ERROR] Failed to build MCP Server image. Check the output above for errors." -ForegroundColor $Colors.Error
#            return $false
#        }
#    } catch {
#        Write-Host "[ERROR] An error occurred while running the build script: $($_.Exception.Message)" -ForegroundColor $Colors.Error
#        return $false
#    }
#}

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
            Write-Host "No OSDFIR Lab related jobs found." -ForegroundColor $Colors.Warning
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
    "uninstall" {
        if (-not $Force) {
            $confirmation = Read-Host "Are you sure you want to uninstall the Helm release '$ReleaseName'? (yes/no)"
            if ($confirmation -ne "yes") {
                Write-Host "Uninstall cancelled." -ForegroundColor $Colors.Warning
                return
            }
        }
        Show-Header "Uninstalling OSDFIR Lab Helm Release"
        helm uninstall $ReleaseName -n $Namespace
    }
    "storage" { Show-Storage }
    "minikube" { Show-MinikubeStatus }
    "docker" {
        Show-Header "Docker Desktop Management"
        if (Test-Docker) {
            Write-Host ""
            Write-Host "Docker is running. Versions:" -ForegroundColor $Colors.Info
            docker version --format "  Client: {{.Client.Version}}"
            docker version --format "  Server: {{.Server.Version}}"
        } else {
            Write-Host "Docker is not running. Attempting to start Docker Desktop..." -ForegroundColor $Colors.Warning
            Start-DockerDesktop
        }
    }
    "deploy" { Start-FullDeployment }
    "shutdown-lab" { Start-SmartCleanup }
    "destroy-lab" { Start-FullCleanup }
    "mcp-setup" { Setup-McpServers }
    "ollama" { Show-OllamaStatus }
    default { Show-Help }
}
