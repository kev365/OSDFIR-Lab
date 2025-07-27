#!/usr/bin/env pwsh
# Update Helm chart dependencies
# Usage: ./scripts/dev/update-helm-deps.ps1

param(
    [switch]$DryRun,
    [switch]$Verbose
)

Write-Host "Updating Helm dependencies..." -ForegroundColor Blue

# Change to helm directory
$originalLocation = Get-Location
try {
    Set-Location "helm"
    
    # Check if Chart.yaml exists
    if (-not (Test-Path "Chart.yaml")) {
        Write-Host "ERROR: Chart.yaml not found in helm directory." -ForegroundColor Red
        exit 1
    }

    if ($DryRun) {
        Write-Host "🔍 DRY RUN: Would update dependencies without making changes" -ForegroundColor Yellow
        Write-Host ""
    }

    # Show current state
    if (Test-Path "Chart.lock") {
        Write-Host "📋 Current Chart.lock:" -ForegroundColor Cyan
        if ($Verbose) {
            $currentLock = Get-Content "Chart.lock" | Select-Object -First 15
            $currentLock | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        } else {
            $deps = helm dependency list 2>$null
            if ($deps) {
                Write-Host $deps -ForegroundColor Gray
            }
        }
        Write-Host ""
    } else {
        Write-Host "ℹ️  No existing Chart.lock found" -ForegroundColor Yellow
    }

    if (-not $DryRun) {
        Write-Host "🔄 Running helm dependency update..." -ForegroundColor Blue
        
        # Update dependencies
        $result = helm dependency update 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to update dependencies:" -ForegroundColor Red
            Write-Host $result -ForegroundColor Red
            exit 1
        }

        Write-Host $result -ForegroundColor Green
        Write-Host ""

        # Show what changed
        Write-Host "📋 Updated Chart.lock:" -ForegroundColor Cyan
        if ($Verbose) {
            $newLock = Get-Content "Chart.lock" | Select-Object -First 15
            $newLock | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        } else {
            $deps = helm dependency list 2>$null
            if ($deps) {
                Write-Host $deps -ForegroundColor Gray
            }
        }
        Write-Host ""

        # Provide next steps
        Write-Host "✅ Dependencies updated successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "📝 Next steps:" -ForegroundColor Cyan
        Write-Host "   git add Chart.lock" -ForegroundColor White
        Write-Host "   git commit -m 'chore: update Helm chart dependencies'" -ForegroundColor White
        Write-Host ""
        Write-Host "💡 Tip: Run './scripts/dev/check-helm-deps.ps1' to verify everything is in sync" -ForegroundColor Yellow
        
    } else {
        Write-Host "🔍 DRY RUN: Would run 'helm dependency update'" -ForegroundColor Yellow
        Write-Host "💡 Run without -DryRun to perform the actual update" -ForegroundColor Cyan
    }

    exit 0
}
catch {
    Write-Host "❌ Error occurred: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Set-Location $originalLocation
} 