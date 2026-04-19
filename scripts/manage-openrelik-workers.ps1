# OpenRelik Worker Management Script
# Manages OpenRelik worker deployments via kubectl scale.
# Requires OpenRelik to already be deployed via manage-osdfir-lab.ps1.

param(
    [Parameter(Position = 0)]
    [ValidateSet("help", "list", "enable", "disable", "enable-all", "disable-all", "start", "stop", "apply", "edit", "status")]
    [string]$Action = "help",

    [Parameter(Position = 1)]
    [string]$Name,

    [string]$ReleaseName = "osdfir-lab",
    [string]$Namespace = "osdfir",
    [switch]$Force = $false,
    [switch]$h = $false
)

# Color constants (matches manage-osdfir-lab.ps1)
$Colors = @{
    Header  = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error   = "Red"
    Info    = "White"
    Gray    = "Gray"
    Command = "Magenta"
}

$ScriptCmd = (Resolve-Path -Relative $MyInvocation.MyCommand.Path) -replace '/', '\'
# The worker catalog lives inline in configs/osdfir-lab-values.yaml under
# openrelik.workers (each entry carries its own enabled/description/source).
# $CatalogPath === $ValuesPath; they are aliases for readability in each call site.
$ValuesPath  = Join-Path $PSScriptRoot "..\configs\osdfir-lab-values.yaml"
$CatalogPath = $ValuesPath

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "== $Title ==" -ForegroundColor $Colors.Header
    Write-Host ("=" * ($Title.Length + 7)) -ForegroundColor $Colors.Header
}

function Show-Help {
    Show-Header "OpenRelik Worker Management"
    Write-Host ""
    Write-Host "Usage: $ScriptCmd <action> [name] [options]" -ForegroundColor $Colors.Warning
    Write-Host ""
    Write-Host "ACTIONS:" -ForegroundColor $Colors.Success
    Write-Host "  list             Show all workers with status and descriptions"
    Write-Host "  enable <name>    Enable a worker (updates catalog + scales to 1 replica)"
    Write-Host "  disable <name>   Disable a worker (updates catalog + scales to 0 replicas)"
    Write-Host "  enable-all       Enable every worker (asks for confirmation - heavy on cluster)"
    Write-Host "  disable-all      Disable every worker"
    Write-Host "  start <name>     Temporarily start a worker (scales to 1, catalog unchanged)"
    Write-Host "  stop <name>      Temporarily stop a worker (scales to 0, catalog unchanged)"
    Write-Host "  apply            Reconcile all workers to match catalog state"
    Write-Host "  edit             Open worker catalog in editor"
    Write-Host "  status           Show running worker pods and replica counts"
    Write-Host "  help             Show this help message"
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor $Colors.Success
    Write-Host "  -Namespace       Kubernetes namespace (default: osdfir)"
    Write-Host "  -ReleaseName     Helm release name (default: osdfir-lab)"
    Write-Host "  -Force           Skip confirmation prompts (use with enable-all/disable-all)"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor $Colors.Header
    Write-Host "  $ScriptCmd list"
    Write-Host "  $ScriptCmd enable plaso"
    Write-Host "  $ScriptCmd disable strings"
    Write-Host "  $ScriptCmd start plaso          # temporary, does not change catalog"
    Write-Host "  $ScriptCmd stop plaso           # temporary, does not change catalog"
    Write-Host "  $ScriptCmd apply                # reconcile cluster to catalog after helm upgrade"
    Write-Host "  $ScriptCmd edit                 # open catalog in editor"
    Write-Host "  $ScriptCmd enable-all           # enable every worker (prompts for confirmation)"
    Write-Host "  $ScriptCmd disable-all -Force   # disable every worker without prompting"
    Write-Host ""
    Show-OpenRelikStatus
}

# --- OpenRelik Status ---

function Test-OpenRelikEnabled {
    if (-not (Test-Path $ValuesPath)) { return $false }
    $content = Get-Content $ValuesPath -Raw
    return $content -match '(?m)^\s+openrelik:\s*\n\s+enabled:\s*true'
}

function Test-OpenRelikDeployed {
    $null = kubectl get deployment "$ReleaseName-openrelik-api" -n $Namespace 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Test-OpenRelikReady {
    param([switch]$Silent)
    $enabled = Test-OpenRelikEnabled
    $deployed = Test-OpenRelikDeployed

    if (-not $enabled) {
        if (-not $Silent) {
            Write-Host "OpenRelik is not enabled." -ForegroundColor $Colors.Error
            Write-Host "  1. Set global.openrelik.enabled to true in configs\osdfir-lab-values.yaml" -ForegroundColor $Colors.Warning
            Write-Host "  2. Run: .\scripts\manage-osdfir-lab.ps1 deploy" -ForegroundColor $Colors.Warning
        }
        return $false
    }

    if (-not $deployed) {
        if (-not $Silent) {
            Write-Host "OpenRelik is enabled but not deployed." -ForegroundColor $Colors.Error
            Write-Host "  Run: .\scripts\manage-osdfir-lab.ps1 deploy" -ForegroundColor $Colors.Warning
        }
        return $false
    }

    return $true
}

function Show-OpenRelikStatus {
    $enabled = Test-OpenRelikEnabled
    $deployed = Test-OpenRelikDeployed

    if ($enabled -and $deployed) {
        Write-Host "  OpenRelik: " -NoNewline -ForegroundColor $Colors.Info
        Write-Host "Deployed" -ForegroundColor $Colors.Success
    } elseif ($enabled -and -not $deployed) {
        Write-Host "  OpenRelik: " -NoNewline -ForegroundColor $Colors.Info
        Write-Host "Enabled but not deployed" -ForegroundColor $Colors.Warning
        Write-Host "  Run: .\scripts\manage-osdfir-lab.ps1 deploy" -ForegroundColor $Colors.Gray
    } else {
        Write-Host "  OpenRelik: " -NoNewline -ForegroundColor $Colors.Info
        Write-Host "Not enabled" -ForegroundColor $Colors.Error
        Write-Host "  Set global.openrelik.enabled: true in configs\osdfir-lab-values.yaml" -ForegroundColor $Colors.Gray
    }
}

# --- Catalog Helpers ---

function Resolve-WorkerName {
    # Accepts a short name ("strings") or full name ("openrelik-worker-strings").
    # Returns the full worker name or $null.
    param([string]$RawName)
    if (-not $RawName) {
        Write-Host "ERROR: Worker name required." -ForegroundColor $Colors.Error
        return $null
    }
    $n = $RawName.Trim()
    if ($n -notmatch '^openrelik-worker-') {
        $n = "openrelik-worker-$n"
    }
    return $n
}

function Get-CatalogWorkers {
    # Worker catalog now lives inline under openrelik.workers in values.yaml.
    # Each entry: name, enabled, description, source, and (if deployable) image/
    # command/env/resources. Names are stored in full form (openrelik-worker-*)
    # because that is what the helm chart requires.
    if (-not (Test-Path $ValuesPath)) {
        Write-Host "ERROR: values.yaml not found at $ValuesPath" -ForegroundColor $Colors.Error
        return $null
    }
    Import-Module powershell-yaml -ErrorAction Stop
    $yaml = Get-Content $ValuesPath -Raw | ConvertFrom-Yaml
    if (-not $yaml.openrelik -or -not $yaml.openrelik.workers) {
        Write-Host "ERROR: openrelik.workers not found in values.yaml" -ForegroundColor $Colors.Error
        return $null
    }
    return $yaml.openrelik.workers
}

function Get-DeploymentReplicas {
    param([string]$WorkerName)
    $deployName = "$ReleaseName-$WorkerName"
    $json = kubectl get deployment $deployName -n $Namespace -o json 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $dep = $json | ConvertFrom-Json
    return @{
        Desired = $dep.spec.replicas
        Ready   = $dep.status.readyReplicas
    }
}

# --- Actions ---

function Invoke-ListWorkers {
    $workers = Get-CatalogWorkers
    if (-not $workers) { return }

    Show-Header "OpenRelik Workers"
    Write-Host ""
    Show-OpenRelikStatus

    # Check if OpenRelik is deployed to show live status
    $isDeployed = Test-OpenRelikDeployed

    $enabledCount = 0
    $disabledCount = 0
    $currentSource = ""

    foreach ($w in $workers) {
        # Section headers
        if ($w.source -ne $currentSource) {
            $currentSource = $w.source
            Write-Host ""
            $label = switch ($currentSource) {
                "official"  { "Official Workers" }
                "community" { "Community Workers" }
                "no-image"  { "Community Workers (no published image - build your own)" }
                default     { "Other Workers" }
            }
            Write-Host "  $label" -ForegroundColor $Colors.Header
            Write-Host "  $('-' * $label.Length)" -ForegroundColor $Colors.Gray
        }

        $shortName = $w.name -replace '^openrelik-worker-', ''
        $enabledTag = if ($w.enabled) { "[ENABLED] " } else { "[DISABLED]" }
        $enabledColor = if ($w.enabled) { $Colors.Success } else { $Colors.Gray }

        if ($w.enabled) { $enabledCount++ } else { $disabledCount++ }

        # Live cluster status
        $runTag = ""
        if ($isDeployed) {
            $rep = Get-DeploymentReplicas -WorkerName $w.name
            if ($rep) {
                $ready = if ($rep.Ready) { $rep.Ready } else { 0 }
                if ($rep.Desired -gt 0 -and $ready -gt 0) {
                    $runTag = " (running)"
                } elseif ($rep.Desired -gt 0) {
                    $runTag = " (starting)"
                } else {
                    $runTag = " (stopped)"
                }
            } else {
                $runTag = " (no deployment)"
            }
        }

        Write-Host -NoNewline "  $enabledTag " -ForegroundColor $enabledColor
        Write-Host -NoNewline "$shortName" -ForegroundColor $Colors.Info
        Write-Host -NoNewline "$runTag" -ForegroundColor $Colors.Gray
        Write-Host " - $($w.description)" -ForegroundColor $Colors.Gray
    }

    Write-Host ""
    $total = $enabledCount + $disabledCount
    Write-Host "  $enabledCount enabled, $disabledCount disabled ($total total)" -ForegroundColor $Colors.Info
    Write-Host ""
}

function Set-WorkerEnabled {
    param([string]$WorkerName, [bool]$Enabled)

    $fullName = Resolve-WorkerName $WorkerName
    if (-not $fullName) { return }

    # Verify worker exists in catalog
    $workers = Get-CatalogWorkers
    if (-not $workers) { return }
    $match = $workers | Where-Object { $_.name -eq $fullName }
    if (-not $match) {
        Write-Host "ERROR: Worker '$fullName' not found in catalog." -ForegroundColor $Colors.Error
        Write-Host "Run '$ScriptCmd list' to see available workers." -ForegroundColor $Colors.Warning
        return
    }

    # No-image workers exist in the catalog for discoverability only. Build-
    # WorkerOverride strips them before helm, so enabling one in the catalog
    # has no runtime effect until the user adds image/command fields.
    if ($Enabled -and $match.source -eq 'no-image') {
        Write-Host "WARNING: '$fullName' has source:no-image; no container image is published." -ForegroundColor $Colors.Warning
        Write-Host "The catalog flag will be set to true, but no Deployment will be created." -ForegroundColor $Colors.Gray
        Write-Host "To run this worker: build an image, add `image:` and `command:` to its entry in configs/osdfir-lab-values.yaml, then redeploy." -ForegroundColor $Colors.Gray
    }

    $currentState = if ($match.enabled) { "true" } else { "false" }
    $targetState = if ($Enabled) { "true" } else { "false" }

    if ($currentState -eq $targetState) {
        $state = if ($Enabled) { "enabled" } else { "disabled" }
        Write-Host "Worker '$fullName' is already $state." -ForegroundColor $Colors.Warning
        return
    }

    # Text-based toggle in catalog file. The file stores short names; accept
    # either short or full form for robustness against older catalogs.
    $shortName = $fullName -replace '^openrelik-worker-', ''
    $nameAlts  = "(?:$([regex]::Escape($shortName))|$([regex]::Escape($fullName)))"
    $lines = Get-Content $CatalogPath
    $found = $false
    $inTarget = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*-\s*name:\s*$nameAlts\s*$") {
            $inTarget = $true
            continue
        }
        if ($inTarget -and $lines[$i] -match '^\s*-\s*name:') {
            break
        }
        if ($inTarget -and $lines[$i] -match '^\s*enabled:\s*(true|false)') {
            $lines[$i] = $lines[$i] -replace 'enabled:\s*(true|false)', "enabled: $targetState"
            $found = $true
            break
        }
    }

    if (-not $found) {
        Write-Host "ERROR: Could not find 'enabled' field for '$fullName' in catalog." -ForegroundColor $Colors.Error
        return
    }

    $lines | Set-Content $CatalogPath -Encoding UTF8
    $verb = if ($Enabled) { "Enabled" } else { "Disabled" }
    Write-Host "$verb '$fullName' in catalog." -ForegroundColor $Colors.Success

    # Scale the deployment to match
    if (-not (Test-OpenRelikReady)) {
        Write-Host "Catalog updated but could not scale deployment." -ForegroundColor $Colors.Warning
        return
    }

    $replicas = if ($Enabled) { 1 } else { 0 }
    Scale-Worker -WorkerName $fullName -Replicas $replicas
}

function Scale-Worker {
    param([string]$WorkerName, [int]$Replicas)
    $deployName = "$ReleaseName-$WorkerName"
    $result = kubectl scale deployment/$deployName -n $Namespace --replicas=$Replicas 2>&1
    if ($LASTEXITCODE -eq 0) {
        $state = if ($Replicas -gt 0) { "started (1 replica)" } else { "stopped (0 replicas)" }
        Write-Host "Worker '$WorkerName' $state." -ForegroundColor $Colors.Success
    } else {
        Write-Host "ERROR: Failed to scale '$deployName': $result" -ForegroundColor $Colors.Error
    }
}

function Invoke-StartWorker {
    param([string]$WorkerName)
    $fullName = Resolve-WorkerName $WorkerName
    if (-not $fullName) { return }
    if (-not (Test-OpenRelikReady)) { return }

    Scale-Worker -WorkerName $fullName -Replicas 1
    Write-Host "NOTE: This is a temporary change. Run '$ScriptCmd apply' to restore catalog state." -ForegroundColor $Colors.Warning
}

function Invoke-StopWorker {
    param([string]$WorkerName)
    $fullName = Resolve-WorkerName $WorkerName
    if (-not $fullName) { return }
    if (-not (Test-OpenRelikReady)) { return }

    Scale-Worker -WorkerName $fullName -Replicas 0
    Write-Host "NOTE: This is a temporary change. Run '$ScriptCmd apply' to restore catalog state." -ForegroundColor $Colors.Warning
}

function Invoke-Apply {
    if (-not (Test-OpenRelikReady)) { return }

    $workers = Get-CatalogWorkers
    if (-not $workers) { return }

    # The catalog intentionally lists workers without a Helm deployment (for
    # discoverability). Fetch all existing deployments once so we can skip those
    # instead of letting kubectl scale emit a noisy error per worker.
    $existingJson = kubectl get deployments -n $Namespace -o json 2>$null
    $existingNames = @()
    if ($LASTEXITCODE -eq 0 -and $existingJson) {
        $existingNames = ($existingJson | ConvertFrom-Json).items.metadata.name
    }

    Show-Header "Applying Worker Catalog"
    Write-Host ""

    $started   = 0
    $stopped   = 0
    $skipped   = 0
    $errors    = 0

    foreach ($w in $workers) {
        $replicas   = if ($w.enabled) { 1 } else { 0 }
        $deployName = "$ReleaseName-$($w.name)"
        $shortName  = $w.name -replace '^openrelik-worker-', ''

        if ($existingNames -notcontains $deployName) {
            Write-Host "  $shortName -> (no deployment)" -ForegroundColor $Colors.Gray
            $skipped++
            continue
        }

        $result = kubectl scale deployment/$deployName -n $Namespace --replicas=$replicas 2>&1
        if ($LASTEXITCODE -eq 0) {
            $state = if ($replicas -gt 0) { "started" } else { "stopped" }
            $color = if ($replicas -gt 0) { $Colors.Success } else { $Colors.Gray }
            Write-Host "  $shortName -> $state" -ForegroundColor $color
            if ($replicas -gt 0) { $started++ } else { $stopped++ }
        } else {
            Write-Host "  $shortName -> ERROR: $result" -ForegroundColor $Colors.Error
            $errors++
        }
    }

    Write-Host ""
    Write-Host -NoNewline "Done: $started started, $stopped stopped, $skipped without deployment" -ForegroundColor $Colors.Success
    if ($errors -gt 0) {
        Write-Host ", $errors errors" -ForegroundColor $Colors.Error
    } else {
        Write-Host ""
    }
}

function Set-AllWorkersEnabled {
    param([bool]$Enabled)

    $workers = Get-CatalogWorkers
    if (-not $workers) { return }

    $verb     = if ($Enabled) { "enable" } else { "disable" }
    $verbCap  = if ($Enabled) { "Enable" } else { "Disable" }
    $target   = if ($Enabled) { "true" } else { "false" }
    $replicas = if ($Enabled) { 1 } else { 0 }

    # Workers that would actually change state
    $changing = @($workers | Where-Object { [bool]$_.enabled -ne $Enabled })
    if ($changing.Count -eq 0) {
        Write-Host "All workers are already $($verb)d." -ForegroundColor $Colors.Warning
        return
    }

    if ($Enabled) {
        Write-Host "WARNING: enable-all will start $($changing.Count) worker(s) simultaneously." -ForegroundColor $Colors.Warning
        Write-Host "This can be heavy on a Minikube/Docker Desktop lab - expect high CPU/memory." -ForegroundColor $Colors.Warning
        Write-Host "Consider enabling only the workers you actively need." -ForegroundColor $Colors.Warning
    }

    if (-not $Force) {
        $answer = Read-Host "$verbCap $($changing.Count) worker(s)? [y/N]"
        if ($answer -notmatch '^[Yy]') {
            Write-Host "Cancelled." -ForegroundColor $Colors.Info
            return
        }
    }

    # Update catalog file (text-based toggle per worker). File stores short
    # names; accept either short or full form for robustness.
    $lines = Get-Content $CatalogPath
    foreach ($w in $changing) {
        $short    = $w.name -replace '^openrelik-worker-', ''
        $nameAlts = "(?:$([regex]::Escape($short))|$([regex]::Escape($w.name)))"
        $inTarget = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*-\s*name:\s*$nameAlts\s*$") {
                $inTarget = $true
                continue
            }
            if ($inTarget -and $lines[$i] -match '^\s*-\s*name:') {
                break
            }
            if ($inTarget -and $lines[$i] -match '^\s*enabled:\s*(true|false)') {
                $lines[$i] = $lines[$i] -replace 'enabled:\s*(true|false)', "enabled: $target"
                break
            }
        }
    }
    $lines | Set-Content $CatalogPath -Encoding UTF8
    Write-Host "Catalog updated: $($changing.Count) worker(s) set to $target." -ForegroundColor $Colors.Success

    if (-not (Test-OpenRelikReady)) {
        Write-Host "Catalog updated but could not scale deployments." -ForegroundColor $Colors.Warning
        return
    }

    foreach ($w in $changing) {
        Scale-Worker -WorkerName $w.name -Replicas $replicas
    }
}

function Invoke-Edit {
    $resolvedPath = Resolve-Path $CatalogPath -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        Write-Host "ERROR: Worker catalog not found at $CatalogPath" -ForegroundColor $Colors.Error
        return
    }

    $editor = $env:EDITOR
    if (-not $editor) { $editor = $env:VISUAL }

    if ($editor) {
        & $editor $resolvedPath
    } elseif (Get-Command code -ErrorAction SilentlyContinue) {
        code $resolvedPath
    } elseif (Get-Command notepad -ErrorAction SilentlyContinue) {
        notepad $resolvedPath
    } else {
        Write-Host "No editor found. Set `$env:EDITOR or open manually:" -ForegroundColor $Colors.Warning
        Write-Host "  $resolvedPath" -ForegroundColor $Colors.Info
        return
    }

    Write-Host ""
    $response = Read-Host "Apply changes now? [Y/n]"
    if ($response -eq '' -or $response -match '^[Yy]') {
        Invoke-Apply
    } else {
        Write-Host "Changes saved to catalog. Run '$ScriptCmd apply' when ready." -ForegroundColor $Colors.Info
    }
}

function Invoke-Status {
    if (-not (Test-OpenRelikReady)) { return }

    Show-Header "OpenRelik Worker Status"
    Write-Host ""

    $deployments = kubectl get deployments -n $Namespace -o json 2>$null | ConvertFrom-Json
    $workerDeps = $deployments.items | Where-Object { $_.metadata.name -match "$ReleaseName-openrelik-worker-" }

    if (-not $workerDeps -or $workerDeps.Count -eq 0) {
        Write-Host "No worker deployments found." -ForegroundColor $Colors.Warning
        return
    }

    # Header
    Write-Host ("  {0,-35} {1,-10} {2,-12} {3}" -f "WORKER", "REPLICAS", "STATUS", "IMAGE") -ForegroundColor $Colors.Header

    foreach ($dep in $workerDeps) {
        $name = $dep.metadata.name -replace "^$([regex]::Escape($ReleaseName))-openrelik-worker-", ''
        $desired = $dep.spec.replicas
        $ready = if ($dep.status.readyReplicas) { $dep.status.readyReplicas } else { 0 }
        $replicaStr = "$ready/$desired"

        $status = if ($desired -eq 0) { "Stopped" }
                  elseif ($ready -eq $desired) { "Running" }
                  else { "Starting" }

        $image = ($dep.spec.template.spec.containers | Select-Object -First 1).image
        $imageShort = $image -replace '^ghcr\.io/(openrelik|openrelik-contrib)/', ''

        $color = switch ($status) {
            "Running"  { $Colors.Success }
            "Starting" { $Colors.Warning }
            "Stopped"  { $Colors.Gray }
        }

        Write-Host ("  {0,-35} {1,-10} " -f $name, $replicaStr) -NoNewline
        Write-Host ("{0,-12} " -f $status) -NoNewline -ForegroundColor $color
        Write-Host $imageShort -ForegroundColor $Colors.Gray
    }
    Write-Host ""
}

# --- Main ---

if ($h) { $Action = "help" }

switch ($Action) {
    "help"        { Show-Help }
    "list"        { Invoke-ListWorkers }
    "enable"      { Set-WorkerEnabled -WorkerName $Name -Enabled $true }
    "disable"     { Set-WorkerEnabled -WorkerName $Name -Enabled $false }
    "enable-all"  { Set-AllWorkersEnabled -Enabled $true }
    "disable-all" { Set-AllWorkersEnabled -Enabled $false }
    "start"       { Invoke-StartWorker -WorkerName $Name }
    "stop"        { Invoke-StopWorker -WorkerName $Name }
    "apply"       { Invoke-Apply }
    "edit"        { Invoke-Edit }
    "status"      { Invoke-Status }
}
