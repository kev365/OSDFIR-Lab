# OSDFIR Minikube Commands Reference

This document provides a comprehensive reference for managing the OSDFIR Minikube infrastructure with AI integration.

## 🎯 Primary Management Script (Recommended)

The `manage-osdfir-lab.ps1` script provides unified control over the entire deployment:

### Full Deployment & Management
```powershell
# Complete deployment (Minikube + Terraform + Services)
./scripts/manage-osdfir-lab.ps1 deploy

# Check status of all components
./scripts/manage-osdfir-lab.ps1 status

# Start port forwarding for all services
./scripts/manage-osdfir-lab.ps1 start

# Stop port forwarding
./scripts/manage-osdfir-lab.ps1 stop

# Get login credentials for services
./scripts/manage-osdfir-lab.ps1 creds

# Check Ollama AI model status
./scripts/manage-osdfir-lab.ps1 ollama

# Complete cleanup (with confirmation)
./scripts/manage-osdfir-lab.ps1 teardown-lab

# Force cleanup without confirmation
./scripts/manage-osdfir-lab.ps1 teardown-lab -Force

# Show help
./scripts/manage-osdfir-lab.ps1 help
```

### Additional Options
```powershell
# Dry run mode (show what would be done)
./scripts/manage-osdfir-lab.ps1 deploy -DryRun
./scripts/manage-osdfir-lab.ps1 teardown-lab -DryRun

# Show Docker Desktop status
./scripts/manage-osdfir-lab.ps1 docker

# Show Minikube status
./scripts/manage-osdfir-lab.ps1 minikube

# Show Helm releases
./scripts/manage-osdfir-lab.ps1 helm

# Show storage information
./scripts/manage-osdfir-lab.ps1 storage
```

## 🔧 Manual Infrastructure Management

### Minikube Management (Built-in to Primary Script)
```powershell
# All Minikube management is now integrated into the primary script
# Use these commands for specific Minikube operations:

# Check Minikube cluster status
./scripts/manage-osdfir-lab.ps1 minikube

# Start Docker Desktop if needed
./scripts/manage-osdfir-lab.ps1 docker

# Full deployment (includes Minikube setup with optimized settings)
./scripts/manage-osdfir-lab.ps1 deploy

# Full cleanup (includes Minikube deletion)
./scripts/manage-osdfir-lab.ps1 teardown-lab -Force
```

### Terraform Infrastructure
```powershell
# Navigate to terraform directory
cd terraform

# Initialize Terraform providers
terraform init

# Preview infrastructure changes
terraform plan

# Apply infrastructure changes
terraform apply -auto-approve

# Destroy infrastructure
terraform destroy -auto-approve

# Show current state
terraform show

# View outputs
terraform output
```

## 📊 Monitoring & Status

### Pod Management
```powershell
# List all pods in osdfir namespace
kubectl get pods -n osdfir

# Watch pod status changes
kubectl get pods -n osdfir --watch

# Describe specific pod
kubectl describe pod <pod-name> -n osdfir

# Get pod resource usage
kubectl top pods -n osdfir

# List all services
kubectl get svc -n osdfir

# List all ingress resources
kubectl get ingress -n osdfir
```

### Helm Management
```powershell
# List Helm releases
helm list -n osdfir

# Show release status
helm status osdfir-lab -n osdfir

# Show release values
helm get values osdfir-lab -n osdfir

# Upgrade release with new values
helm upgrade osdfir-lab ./helm --namespace osdfir --values helm/osdfir-lab-values.yaml

# Uninstall release
helm uninstall osdfir-lab --namespace osdfir
```

## 🔍 Logging & Debugging

### View Logs
```powershell
# Follow logs for specific pod
kubectl logs -f <pod-name> -n osdfir

# View logs for all pods with specific label
kubectl logs -l app=timesketch -n osdfir
kubectl logs -l app=ollama -n osdfir
kubectl logs -l app.kubernetes.io/name=openrelik-api -n osdfir

# View logs for specific container in multi-container pod
kubectl logs <pod-name> -c <container-name> -n osdfir

# View previous logs (if pod restarted)
kubectl logs <pod-name> --previous -n osdfir
```

### Debugging Commands
```powershell
# Execute commands inside pods
kubectl exec -it <pod-name> -n osdfir -- /bin/bash
kubectl exec -it <pod-name> -n osdfir -- /bin/sh

# Check cluster info
kubectl cluster-info

# Check node status
kubectl get nodes
kubectl top nodes

# Check cluster events
kubectl get events -n osdfir --sort-by=.metadata.creationTimestamp
```

## 🤖 AI/Ollama Management

### Ollama Operations
```powershell
# List available models in Ollama
kubectl exec -n osdfir <ollama-pod-name> -- ollama list

# Check models via API
kubectl exec -n osdfir <ollama-pod-name> -- curl -s http://localhost:11434/api/tags

# Test model interaction
kubectl exec -n osdfir <ollama-pod-name> -- ollama run gemma2:2b "Analyze this forensic artifact"

# View Ollama logs
kubectl logs -f <ollama-pod-name> -n osdfir

# Direct access to Ollama API
kubectl port-forward svc/ollama 11434:11434 -n osdfir
```

### AI Integration Testing
```powershell
# Test OpenRelik to Ollama connectivity
kubectl exec -n osdfir <openrelik-api-pod> -- curl -s http://ollama.osdfir.svc.cluster.local:11434/api/tags

# Check AI worker status
kubectl logs -l app.kubernetes.io/name=openrelik-worker-analyzer-config -n osdfir

# Test Timesketch LLM features (access via port-forward)
curl -X POST http://localhost:5000/api/v1/sketches/<sketch-id>/analyzer/ \
  -H "Content-Type: application/json" \
  -d '{"analyzer_name": "llm_analyzer"}'
```

## 🌐 Port Forwarding & Access

### Service Access
```powershell
# Timesketch (Timeline Analysis)
kubectl port-forward svc/osdfir-lab-timesketch 5000:5000 -n osdfir
# Access: http://localhost:5000

# OpenRelik UI (Evidence Processing)
kubectl port-forward svc/osdfir-lab-openrelik-ui 8711:8711 -n osdfir
# Access: http://localhost:8711

# OpenRelik API
kubectl port-forward svc/osdfir-lab-openrelik-api 8710:8710 -n osdfir
# Access: http://localhost:8710

# Ollama AI Server
kubectl port-forward svc/ollama 11434:11434 -n osdfir
# Access: http://localhost:11434

# Yeti Frontend
kubectl port-forward svc/osdfir-lab-yeti-frontend 3000:3000 -n osdfir
# Access: http://localhost:3000

# HashR
kubectl port-forward svc/osdfir-lab-hashr 8080:8080 -n osdfir
# Access: http://localhost:8080
```

## 🔐 Credentials & Secrets

### Get Service Credentials
```powershell
# List all secrets
kubectl get secret -n osdfir

# Get Timesketch admin password
kubectl get secret osdfir-lab-timesketch-credentials -n osdfir -o jsonpath="{.data.admin_password}" | base64 --decode

# Get PostgreSQL passwords
kubectl get secret osdfir-lab-timesketch-postgresql -n osdfir -o jsonpath="{.data.postgres-password}" | base64 --decode

# Get Redis password
kubectl get secret osdfir-lab-timesketch-redis -n osdfir -o jsonpath="{.data.redis-password}" | base64 --decode
```

## 🛠️ Troubleshooting

### Common Issues
```powershell
# Check if Minikube is running
minikube status --profile=osdfir

# Restart Minikube tunnel
minikube tunnel --profile=osdfir --cleanup

# Check Docker Desktop status
docker info

# Reset Kubernetes context
kubectl config use-context osdfir

# Check resource limits
kubectl describe node minikube

# Clear failed pods
kubectl delete pods --field-selector=status.phase=Failed -n osdfir
```

### Emergency Recovery
```powershell
# Complete reset (nuclear option)
./scripts/manage-osdfir-lab.ps1 teardown-lab -Force
./scripts/manage-osdfir-lab.ps1 deploy

# Restart specific service
kubectl rollout restart deployment/<deployment-name> -n osdfir

# Scale deployment
kubectl scale deployment/<deployment-name> --replicas=0 -n osdfir
kubectl scale deployment/<deployment-name> --replicas=1 -n osdfir
```

## 📱 Useful Utilities

### Minikube Dashboard
```powershell
# Open Kubernetes dashboard
minikube dashboard --profile=osdfir
```

### Quick Status Checks
```powershell
# All-in-one status check
kubectl get all -n osdfir

# Resource usage overview
kubectl top nodes
kubectl top pods -n osdfir

# Check persistent volume claims
kubectl get pvc -n osdfir

# Check ingress status
kubectl get ingress -n osdfir
```

---

**💡 Tip**: The `manage-osdfir-lab.ps1` script is now fully self-contained and handles all dependencies including Minikube management, Docker detection, and resource optimization automatically. 