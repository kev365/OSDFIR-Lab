output "namespace" {
  description = "Name of the Kubernetes namespace created"
  value       = kubernetes_namespace.osdfir.metadata[0].name
}

output "pvc_name" {
  description = "Name of the PersistentVolumeClaim created"
  value       = kubernetes_persistent_volume_claim.osdfirvolume.metadata[0].name
}

output "helm_release" {
  description = "Name of the Helm release deployed"
  value       = helm_release.osdfir.name
} 