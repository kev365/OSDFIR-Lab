# OSDFIR Minikube Management Script
# Unified tool for managing OSDFIR deployment, services, and credentials on Minikube

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("help", "status", "start", "stop", "restart", "logs", "cleanup", "creds", "jobs", "helm", "uninstall", "storage", "minikube", "deploy", "undeploy", "ollama")]
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
    Show-Header "OSDFIR Minikube Management Tool"
    Write-Host ""
    Write-Host "Usage: .\manage-osdfir.ps1 [action] [options]" -ForegroundColor $Colors.Warning
    Write-Host ""
    Write-Host "Actions:" -ForegroundColor $Colors.Success
    Write-Host "  help      - Show this help message"
    Write-Host "  status    - Show deployment and service status"
    Write-Host "  start     - Start port forwarding for services"
    Write-Host "  stop      - Stop port forwarding jobs"
    Write-Host "  restart   - Restart port forwarding jobs"
    Write-Host "  logs      - Show logs from services"
    Write-Host "  creds     - Get service credentials"
    Write-Host "  jobs      - Manage background jobs"
    Write-Host "  cleanup   - Clean up OSDFIR deployment"
    Write-Host "  helm      - List Helm releases and show release status"
    Write-Host "  uninstall - Uninstall the Helm release"
    Write-Host "  storage   - Show PV storage utilization"
    Write-Host "  minikube  - Show Minikube cluster status"
    Write-Host "  deploy    - Full deployment (Minikube + Terraform + Services)"
    Write-Host "  undeploy  - Full cleanup (Services + Terraform + Minikube)"
    Write-Host "  ollama    - Show Ollama AI model status and connectivity"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor $Colors.Success
    Write-Host "  -h                Show help (alias for help action)"
    Write-Host "  -ReleaseName      Helm release name (default: osdfir-lab)"
    Write-Host "  -Namespace        Kubernetes namespace (default: osdfir)"
    Write-Host "  -Service          Specific service for creds (all, timesketch, openrelik)"
    Write-Host "  -Force            Force operations without confirmation"
    Write-Host "  -DryRun           Show what would be done without executing"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor $Colors.Header
    Write-Host "  .\manage-osdfir.ps1 -h"
    Write-Host "  .\manage-osdfir.ps1 deploy"
    Write-Host "  .\manage-osdfir.ps1 status"
    Write-Host "  .\manage-osdfir.ps1 start"
    Write-Host "  .\manage-osdfir.ps1 creds -Service timesketch"
    Write-Host "  .\manage-osdfir.ps1 logs"
    Write-Host "  .\manage-osdfir.ps1 ollama"
    Write-Host "  .\manage-osdfir.ps1 undeploy -Force"
}

function Test-Prerequisites {
    $missing = @()
    
    # Check required tools
    $tools = @("minikube", "kubectl", "terraform", "helm", "docker")
    foreach ($tool in $tools) {
        try {
            & $tool version > $null 2>&1
            if ($LASTEXITCODE -ne 0) { $missing += $tool }
        } catch {
            $missing += $tool
        }
    }
    
    if ($missing.Count -gt 0) {
        Write-Host "ERROR: Missing required tools: $($missing -join ', ')" -ForegroundColor $Colors.Error
        Write-Host "Please install all required tools before proceeding." -ForegroundColor $Colors.Warning
        return $false
    }
    
    return $true
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
        Write-Host "TIP: Run .\manage-osdfir.ps1 deploy to start the full environment" -ForegroundColor $Colors.Info
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
        Write-Host "TIP: Run .\manage-osdfir.ps1 deploy to start the full environment" -ForegroundColor $Colors.Info
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
        Write-Host "  TIP: Run .\manage-osdfir.ps1 start" -ForegroundColor $Colors.Info
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
        Write-Host "TIP: Run .\manage-osdfir.ps1 deploy to start the full environment" -ForegroundColor $Colors.Info
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
    Write-Host "TIP: Use .\manage-osdfir.ps1 creds to get login credentials" -ForegroundColor $Colors.Info
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
        Write-Host "1. Start Minikube cluster with tunnel" -ForegroundColor $Colors.Info
        Write-Host "2. Initialize and apply Terraform configuration" -ForegroundColor $Colors.Info
        Write-Host "3. Start port forwarding for services" -ForegroundColor $Colors.Info
        return
    }
    
    # Step 1: Start Minikube
    Write-Host "Step 1: Starting Minikube cluster..." -ForegroundColor $Colors.Info
    & "$PSScriptRoot\start-minikube.ps1" -deploy
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to start Minikube" -ForegroundColor $Colors.Error
        return
    }
    
    # Step 2: Deploy with Terraform
    Write-Host ""
    Write-Host "Step 2: Deploying OSDFIR with Terraform..." -ForegroundColor $Colors.Info
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
    
    # Step 3: Wait for pods to be ready
    Write-Host ""
    Write-Host "Step 3: Waiting for pods to be ready..." -ForegroundColor $Colors.Info
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
        Write-Host "You can check status with: .\manage-osdfir.ps1 status" -ForegroundColor $Colors.Info
    }
    
    # Step 4: Start services
    Write-Host ""
    Write-Host "Step 4: Starting port forwarding..." -ForegroundColor $Colors.Info
    Start-Services
    
    Write-Host ""
    Write-Host "Deployment completed!" -ForegroundColor $Colors.Success
    Write-Host "Use .\manage-osdfir.ps1 creds to get login credentials" -ForegroundColor $Colors.Info
    Write-Host "Use .\manage-osdfir.ps1 ollama to check AI model status" -ForegroundColor $Colors.Info
}

function Start-FullCleanup {
    Show-Header "Full OSDFIR Cleanup"
    
    if (-not $Force) {
        $confirmation = Read-Host "This will destroy the entire OSDFIR environment. Are you sure? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-Host "Cleanup cancelled." -ForegroundColor $Colors.Warning
            return
        }
    }
    
    if ($DryRun) {
        Write-Host "DRY RUN: Would execute the following steps:" -ForegroundColor $Colors.Warning
        Write-Host "1. Stop all port forwarding jobs" -ForegroundColor $Colors.Info
        Write-Host "2. Destroy Terraform resources" -ForegroundColor $Colors.Info
        Write-Host "3. Delete Minikube cluster" -ForegroundColor $Colors.Info
        return
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
    & "$PSScriptRoot\start-minikube.ps1" -delete -f
    
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
    "deploy" { Start-FullDeployment }
    "undeploy" { Start-FullCleanup }
    "ollama" { Show-OllamaStatus }
    default { Show-Help }
}
