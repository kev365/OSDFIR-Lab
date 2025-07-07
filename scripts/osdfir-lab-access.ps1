<#
.SYNOPSIS
    Start port forwarding for OSDFIR Lab services and display access credentials.
.DESCRIPTION
    Launches background jobs for port forwarding Timesketch, Yeti, and OpenRelik services
    in the 'osdfir' namespace and retrieves their login passwords from Kubernetes secrets.
#>

Param(
    [switch]$all,
    [switch]$stop
)

# Function to decode base64 secret
function Decode-Secret {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Base64String
    )
    $bytes = [System.Convert]::FromBase64String($Base64String)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

# Stop flag handling: terminate all port-forward jobs and exit
if ($stop) {
    Write-Output "Stopping all port-forward jobs..."
    $jobs = @("pf-Timesketch", "pf-OpenRelik-UI", "pf-OpenRelik-API", "pf-TS-Postgres", "pf-TS-Redis", "pf-OR-Postgres", "pf-OR-Redis")
    foreach ($jobName in $jobs) {
        $job = Get-Job -Name $jobName -ErrorAction SilentlyContinue
        if ($job) {
            Write-Output "Stopping $jobName..."
            Stop-Job -Job $job
            Remove-Job -Job $job
        } else {
            Write-Output "No job $jobName to stop."
        }
    }
    return
}

# Start UI port-forward jobs
Write-Output "Starting UI port-forward jobs..."
Start-Job -Name "pf-Timesketch" -ScriptBlock { & kubectl --namespace osdfir port-forward service/osdfir-lab-timesketch 5000:5000 }
Start-Job -Name "pf-OpenRelik-UI" -ScriptBlock { & kubectl --namespace osdfir port-forward service/osdfir-lab-openrelik 8711:8711 }
Start-Job -Name "pf-OpenRelik-API" -ScriptBlock { & kubectl --namespace osdfir port-forward service/osdfir-lab-openrelik-api 8710:8710 }

# Start database port-forward jobs if -all
if ($all) {
    Write-Output "Starting database port-forward jobs..."
    Start-Job -Name "pf-TS-Postgres" -ScriptBlock { & kubectl --namespace osdfir port-forward service/osdfir-lab-timesketch-postgres 5432:5432 }
    Start-Job -Name "pf-TS-Redis" -ScriptBlock { & kubectl --namespace osdfir port-forward service/osdfir-lab-timesketch-redis 6379:6379 }
    Start-Job -Name "pf-OR-Postgres" -ScriptBlock { & kubectl --namespace osdfir port-forward service/osdfir-lab-openrelik-postgres 5433:5432 }
    Start-Job -Name "pf-OR-Redis" -ScriptBlock { & kubectl --namespace osdfir port-forward service/osdfir-lab-openrelik-redis 6380:6379 }
}

Write-Output "Port forwarding jobs started."

# Database Access endpoints and credentials
if ($all) {
    Write-Output "`nDatabase Credentials:"
    $tsDBB64 = kubectl get secret --namespace osdfir osdfir-lab-timesketch-secret -o jsonpath="{.data.postgres-user}"
    $tsDBPass = Decode-Secret -Base64String $tsDBB64
    Write-Output " [Timesketch PostgreSQL]"
    Write-Output " - DB Access : http://localhost:5432"
    Write-Output " - Password  : $tsDBPass"
    $tsRedisB64 = kubectl get secret --namespace osdfir osdfir-lab-timesketch-secret -o jsonpath="{.data.redis-user}"
    $tsRedisPass = Decode-Secret -Base64String $tsRedisB64
    Write-Output "`n [Timesketch Redis]"
    Write-Output " - DB Access : http://localhost:6379"
    Write-Output " - Password  : $tsRedisPass"
    $orDBB64 = kubectl get secret --namespace osdfir osdfir-lab-openrelik-secret -o jsonpath="{.data.postgres-user}"
    $orDBPass = Decode-Secret -Base64String $orDBB64
    Write-Output "`n [OpenRelik PostgreSQL]"
    Write-Output " - DB Access : http://localhost:5433"
    Write-Output " - Password  : $orDBPass"
    $orRedisB64 = kubectl get secret --namespace osdfir osdfir-lab-openrelik-secret -o jsonpath="{.data.redis-user}"
    $orRedisPass = Decode-Secret -Base64String $orRedisB64
    Write-Output "`n [OpenRelik Redis]"
    Write-Output " - DB Access : http://localhost:6380"
    Write-Output " - Password  : $orRedisPass"

    # Access instructions
    Write-Output "`nAccess Instructions:"
    Write-Output " - Timesketch PostgreSQL CLI: psql -h localhost -p 5432 -U postgres -d timesketch"
    Write-Output " - Connection URL: postgresql://postgres:$tsDBPass@localhost:5432/timesketch"
    Write-Output "`n - Timesketch Redis CLI: redis-cli -h localhost -p 6379 -a $tsRedisPass"
    Write-Output " - Connection URL: redis://:$tsRedisPass@localhost:6379"
    Write-Output "`n - OpenRelik PostgreSQL CLI: psql -h localhost -p 5433 -U postgres -d openrelik"
    Write-Output " - Connection URL: postgresql://postgres:$orDBPass@localhost:5433/openrelik"
    Write-Output "`n - OpenRelik Redis CLI: redis-cli -h localhost -p 6380 -a $orRedisPass"
    Write-Output " - Connection URL: redis://:$orRedisPass@localhost:6380"
}

# UI Endpoints and credentials
Write-Output "`nUI Endpoints:"
Write-Output " - Timesketch:    http://localhost:5000"
Write-Output " - OpenRelik:     http://localhost:8711"
Write-Output " - OpenRelik API: http://localhost:8710/api/v1/docs/"

Write-Output "`nUI Credentials:"
$tsB64 = kubectl get secret --namespace osdfir osdfir-lab-timesketch-secret -o jsonpath="{.data.timesketch-user}"
$tsPassword = Decode-Secret -Base64String $tsB64
Write-Output " [Timesketch]"
Write-Output " - Login: timesketch"
Write-Output " - Password: $tsPassword"
$orB64 = kubectl get secret --namespace osdfir osdfir-lab-openrelik-secret -o jsonpath="{.data.openrelik-user}"
$orPassword = Decode-Secret -Base64String $orB64
Write-Output "`n [OpenRelik]"
Write-Output " - Login: openrelik"
Write-Output " - Password: $orPassword"

# Pod Management Tips
Write-Output "`nPod Management Tips:"
Write-Output " - List pods: kubectl get pods -n osdfir"
Write-Output " - Watch pods: kubectl get pods -n osdfir --watch"
Write-Output " - Describe pod: kubectl describe pod <pod-name> -n osdfir"
Write-Output " - Exec into pod: kubectl exec -it <pod-name> -n osdfir -- /bin/sh" 