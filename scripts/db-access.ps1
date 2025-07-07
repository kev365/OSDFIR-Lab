<#
.SYNOPSIS
    Start/stop database port-forwards and web UIs for OSDFIR Lab.
.DESCRIPTION
    - Without flags, starts port-forward jobs for Timesketch and OpenRelik Postgres/Redis,
      retrieves their credentials, and launches Adminer, Redis Commander, and pgweb via Docker.
    - Use -stop to terminate all related background jobs and containers.
.PARAMETER stop
    Stops port-forward jobs and Docker containers launched by this script.
#>
Param(
    [switch]$stop
)

# Function to decode base64 secrets
function Decode-Secret {
    param (
        [Parameter(Mandatory=$true)][string]$Base64String
    )
    $bytes = [System.Convert]::FromBase64String($Base64String)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

if ($stop) {
    Write-Output "Stopping DB port-forward jobs..."
    $jobs = @("pf-TS-Postgres","pf-TS-Redis","pf-OR-Postgres","pf-OR-Redis")
    foreach ($jobName in $jobs) {
        $job = Get-Job -Name $jobName -ErrorAction SilentlyContinue
        if ($job) {
            Stop-Job -Job $job | Out-Null
            Remove-Job -Job $job | Out-Null
            Write-Output "Stopped job: $jobName"
        } else {
            Write-Output "No job to stop: $jobName"
        }
    }
    Write-Output "Stopping DB UI containers..."
    $containers = @("adminer","redis-commander","pgweb")
    foreach ($c in $containers) {
        docker rm -f $c | Out-Null
        Write-Output "Removed container (if existed): $c"
    }
    return
}

# Start DB port-forward jobs
Write-Output "Starting DB port-forward jobs..."
Start-Job -Name "pf-TS-Postgres" -ScriptBlock { & kubectl port-forward --address 0.0.0.0 svc/osdfir-lab-timesketch-postgres 5432:5432 -n osdfir } | Out-Null
Start-Job -Name "pf-TS-Redis"    -ScriptBlock { & kubectl port-forward --address 0.0.0.0 svc/osdfir-lab-timesketch-redis 6379:6379 -n osdfir }    | Out-Null
Start-Job -Name "pf-OR-Postgres" -ScriptBlock { & kubectl port-forward --address 0.0.0.0 svc/osdfir-lab-openrelik-postgres 5433:5432 -n osdfir }  | Out-Null
Start-Job -Name "pf-OR-Redis"    -ScriptBlock { & kubectl port-forward --address 0.0.0.0 svc/osdfir-lab-openrelik-redis 6380:6379 -n osdfir }    | Out-Null
Write-Output "DB port-forwards started.`n"

# Retrieve DB credentials
$tsDBB64    = kubectl get secret -n osdfir osdfir-lab-timesketch-secret    -o jsonpath="{.data.postgres-user}"
$tsDBPass   = Decode-Secret -Base64String $tsDBB64
$tsRedisB64 = kubectl get secret -n osdfir osdfir-lab-timesketch-secret    -o jsonpath="{.data.redis-user}"
$tsRedisPass= Decode-Secret -Base64String $tsRedisB64
$orDBB64    = kubectl get secret -n osdfir osdfir-lab-openrelik-secret -o jsonpath="{.data.postgres-user}"
$orDBPass   = Decode-Secret -Base64String $orDBB64
$orRedisB64 = kubectl get secret -n osdfir osdfir-lab-openrelik-secret -o jsonpath="{.data.redis-user}"
$orRedisPass= Decode-Secret -Base64String $orRedisB64

# Launch browser-based DB UIs
Write-Output "Launching Adminer (Postgres UI) at http://localhost:8080..."
docker run --rm -d --name adminer --add-host host.docker.internal:host-gateway -p 8080:8080 adminer > $null 2>&1

Write-Output "Launching Redis Commander at http://localhost:8081..."
docker run --rm -d --name redis-commander --add-host host.docker.internal:host-gateway -p 8081:8081 rediscommander/redis-commander --redis-host host.docker.internal --redis-port 6379 --redis-password $tsRedisPass > $null 2>&1

# Health check Redis Commander UI
Write-Output "Checking Redis Commander UI at http://localhost:8081..."
Start-Sleep -Seconds 5
try {
    Invoke-WebRequest -Uri 'http://localhost:8081' -UseBasicParsing -ErrorAction Stop | Out-Null
    Write-Output 'Redis Commander UI is reachable.'
} catch {
    # Capture Redis Commander UI error
    $redisUIError = $_.Exception.Message
    if ($_.Exception.InnerException) {
        $redisUIError += " | " + $_.Exception.InnerException.Message
    }
    Write-Output "ERROR: Cannot reach Redis Commander UI at http://localhost:8081: $redisUIError"
    Write-Output "-- Redis Commander container logs --"
    docker logs redis-commander --tail 20 | ForEach-Object { Write-Output "    $_" }
}

Write-Output "Launching pgweb (Postgres Web UI) at http://localhost:8082..."
docker run --rm -d --name pgweb --add-host host.docker.internal:host-gateway -p 8082:8081 sosedoff/pgweb --db-url "postgresql://postgres:$tsDBPass@host.docker.internal:5432/timesketch" > $null 2>&1

# Health check pgweb UI
Write-Output "Checking pgweb UI at http://localhost:8082..."
Start-Sleep -Seconds 5
try {
    Invoke-WebRequest -Uri 'http://localhost:8082' -UseBasicParsing -ErrorAction Stop | Out-Null
    Write-Output 'pgweb UI is reachable.'
} catch {
    # Capture pgweb UI error
    $pgwebUIError = $_.Exception.Message
    if ($_.Exception.InnerException) {
        $pgwebUIError += " | " + $_.Exception.InnerException.Message
    }
    Write-Output "ERROR: Cannot reach pgweb UI at http://localhost:8082: $pgwebUIError"
    Write-Output "-- pgweb container logs --"
    docker logs pgweb --tail 20 | ForEach-Object { Write-Output "    $_" }
}

# Summary of Access Information
Write-Output "`n=== Access Summary ==="
Write-Output "Database Endpoints:"  
Write-Output " - Timesketch PostgreSQL: localhost:5432"  
Write-Output " - Timesketch Redis:      localhost:6379"  
Write-Output " - OpenRelik PostgreSQL:  localhost:5433"  
Write-Output " - OpenRelik Redis:       localhost:6380"  
Write-Output "`nDatabase Credentials:"  
Write-Output " [Timesketch PostgreSQL] Password: $tsDBPass"  
Write-Output " [Timesketch Redis]      Password: $tsRedisPass"  
Write-Output " [OpenRelik PostgreSQL]  Password: $orDBPass"  
Write-Output " [OpenRelik Redis]       Password: $orRedisPass"  

# Web UI form details
Write-Output "`nAdminer (Postgres UI) at http://localhost:8080"
Write-Output " Form fields:"  
Write-Output "  - System:   PostgreSQL"
Write-Output "  - Server:   host.docker.internal:5432"
Write-Output "  - Username: postgres"
Write-Output "  - Password: $tsDBPass"
Write-Output "  - Database: timesketch"
  
Write-Output "`nRedis Commander (Redis UI) at http://localhost:8081"
Write-Output " Form fields:"  
Write-Output "  - Host:     host.docker.internal"
Write-Output "  - Port:     6379"
Write-Output "  - Password: $tsRedisPass"
  
Write-Output "`npgweb (Postgres Web UI) at http://localhost:8082"
Write-Output " Auto-configured via --db-url"
  
Write-Output "`nTo stop all: .\db-access.ps1 -stop"

# Display saved UI error messages
if ($redisUIError) {
    Write-Output "`nRedis Commander UI Error: $redisUIError"
}
if ($pgwebUIError) {
    Write-Output "pgweb UI Error: $pgwebUIError"
} 