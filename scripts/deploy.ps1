# deploy.ps1
# This script deploys the OSDFIR stack using the local Helm chart.

# Variables
$ReleaseName = "osdfir-minikube"
$Namespace = "osdfir"
$ChartPath = "../helm"

Write-Host "--- Step 1: Applying Kubernetes manifests ---"
Write-Host "Creating namespace: $Namespace"
kubectl apply -f ../manifests/namespace.yaml
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply namespace manifest."
    exit 1
}

Write-Host "Creating PersistentVolumeClaim: osdfirvolume"
kubectl apply -f ../manifests/pvc.yaml
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply PVC manifest."
    exit 1
}
Write-Host "Manifests applied successfully."
Write-Host ""


Write-Host "--- Step 2: Updating Helm dependencies ---"
helm dependency update $ChartPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to update Helm dependencies. Please check your Helm setup."
    exit 1
}
Write-Host "Helm dependencies updated."
Write-Host ""


Write-Host "--- Step 3: Deploying the OSDFIR stack with Helm ---"
helm upgrade --install $ReleaseName $ChartPath --namespace $Namespace
if ($LASTEXITCODE -ne 0) {
    Write-Error "Helm deployment failed. Please check the output for errors."
    exit 1
}
Write-Host ""
Write-Host "---------------------------------------------------------"
Write-Host "Deployment complete! It may take several minutes for all pods to become ready."
Write-Host "Run 'kubectl get pods -n $Namespace --watch' to check the status."
Write-Host "---------------------------------------------------------" 