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

# Kubernetes namespace
resource "kubernetes_namespace" "osdfir" {
  metadata {
    name = var.namespace
  }
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
    file("${path.module}/../helm/osdfir-lab-values.yaml"),
  ]

  # Prevent Terraform from timing out waiting for all pods; adjust as needed
  timeout = 600
  wait    = false

  depends_on = [
    kubernetes_persistent_volume_claim.osdfirvolume,
  ]
}