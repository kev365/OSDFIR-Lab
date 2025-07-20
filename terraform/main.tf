terraform {
  required_version = ">= 1.0.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0.0"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand("~/.kube/config")
  config_context = "osdfir"
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand("~/.kube/config")
    config_context = "osdfir"
  }
}

# Create tar.gz archive of Timesketch data directory using Windows tar command
resource "null_resource" "timesketch_configs" {
  # Recreate archive when any file in the data directory changes
  triggers = {
    data_dir_hash = sha256(join("", [for f in fileset("${path.module}/../helm/configs/data", "**") : filesha256("${path.module}/../helm/configs/data/${f}")]))
  }

  provisioner "local-exec" {
    command     = "cd ../helm/configs/data; tar -czf ../../../terraform/ts-configs.tar.gz ."
    working_dir = path.module
    interpreter = ["powershell", "-Command"]
  }
}

# Read the created tar.gz file
data "local_file" "timesketch_configs_tar" {
  filename   = "${path.module}/ts-configs.tar.gz"
  depends_on = [null_resource.timesketch_configs]
}

# Kubernetes namespace
resource "kubernetes_namespace" "osdfir" {
  metadata {
    name = var.namespace
  }
}

# Create ConfigMap with base64 encoded tarball (uses Timesketch's built-in support)
resource "kubernetes_config_map" "timesketch_configs" {
  metadata {
    name      = "${var.helm_release_name}-timesketch-configs"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }

  # Use the exact key name that Timesketch init script expects
  data = {
    "ts-configs.tgz.b64" = data.local_file.timesketch_configs_tar.content_base64
  }
  
  depends_on = [kubernetes_namespace.osdfir, null_resource.timesketch_configs]
}

# PersistentVolumeClaim for shared storage
resource "kubernetes_persistent_volume_claim" "osdfirvolume" {
  metadata {
    name      = var.pvc_name
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.pvc_storage
      }
    }
    storage_class_name = var.storage_class_name
  }
}

# Helm release for OSDFIR Infrastructure
resource "helm_release" "osdfir" {
  name       = var.helm_release_name
  chart      = "../helm"
  namespace  = kubernetes_namespace.osdfir.metadata[0].name
  values     = [
    file("${path.module}/../helm/values.yaml"),
    file("${path.module}/../helm/configs/osdfir-lab-values.yaml"),
  ]

  # Configure Timesketch to use our ConfigMap
  set = [
    {
      name  = "timesketch.config.existingConfigMap"
      value = kubernetes_config_map.timesketch_configs.metadata[0].name
    }
  ]

  # Prevent Terraform from timing out waiting for all pods; adjust as needed
  timeout = 600
  wait    = false

  depends_on = [
    kubernetes_persistent_volume_claim.osdfirvolume,
    kubernetes_config_map.timesketch_configs,
  ]
}
