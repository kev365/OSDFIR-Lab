#!/usr/bin/env pwsh
# Check if Helm dependencies are up to date
# Usage: ./scripts/dev/check-helm-deps.ps1

param(
    [switch]$Verbose
)

Write-Host "Checking Helm dependencies..." -ForegroundColor Blue

# Change to helm directory
$originalLocation = Get-Location
try {
    Set-Location "helm"
    
    # Check if Chart.yaml exists
    if (-not (Test-Path "Chart.yaml")) {
        Write-Host "ERROR: Chart.yaml not found in helm directory." -ForegroundColor Red
        exit 1
    }

    # Check if Chart.lock exists
    if (-not (Test-Path "Chart.lock")) {
        Write-Host "ERROR: Chart.lock not found. Run 'helm dependency update' first." -ForegroundColor Red
        Write-Host "TIP: cd helm && helm dependency update" -ForegroundColor Yellow
        exit 1
    }

    if ($Verbose) {
        Write-Host "Current dependency status:" -ForegroundColor Cyan
    }

    # Check if dependencies are up to date
    $result = helm dependency list 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Error checking dependencies:" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
        exit 1
    }

    if ($Verbose) {
        Write-Host $result -ForegroundColor Gray
    }

    # Look for "missing" in the output
    if ($result -match "missing") {
        Write-Host "ERROR: Dependencies are out of sync!" -ForegroundColor Red
        Write-Host "Dependency status:" -ForegroundColor Yellow
        Write-Host $result -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To fix this, run:" -ForegroundColor Cyan
        Write-Host "   cd helm" -ForegroundColor White
        Write-Host "   helm dependency update" -ForegroundColor White
        Write-Host "   git add Chart.lock" -ForegroundColor White
        Write-Host "   git commit -m 'Update Helm dependencies'" -ForegroundColor White
        exit 1
    }

    # Check if charts directory exists and has the right charts
    if (Test-Path "charts") {
        $chartDirs = Get-ChildItem "charts" -Directory | Select-Object -ExpandProperty Name
        if ($Verbose -and $chartDirs) {
            Write-Host "Available charts: $($chartDirs -join ', ')" -ForegroundColor Gray
        }
    }

    Write-Host "Helm dependencies are up to date!" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $originalLocation
} 