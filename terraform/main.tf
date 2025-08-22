terraform {
  required_version = ">= 1.0.0"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.0.0" }
    helm       = { source = "hashicorp/helm",       version = ">= 2.0.0" }
    local      = { source = "hashicorp/local",      version = ">= 2.0.0" }
    null       = { source = "hashicorp/null",       version = ">= 3.0.0" }
  }
}

# Use the current kubectl context (which should be "osdfir")
provider "kubernetes" {
  config_path    = pathexpand("~/.kube/config")
  config_context = "osdfir"
}

# Add this Helm provider configuration (from the article):
provider "helm" {
  kubernetes = {
    config_path    = pathexpand("~/.kube/config")
    config_context = "osdfir"
  }
}

# Namespace
resource "kubernetes_namespace" "osdfir" {
  metadata { name = var.namespace }
}

# ConfigMap that carries the prebuilt base64'ed tarball from your repo
# Make sure this path matches where your workflow writes the file.
# (Currently: helm-addons/files/ts-configs.tgz.b64)
resource "kubernetes_config_map" "timesketch_configs" {
  metadata {
    name      = "${var.helm_release_name}-ts-configs"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }

  data = {
    "ts-configs.tgz.b64" = file("${path.module}/../helm-addons/files/ts-configs.tgz.b64")
  }

  depends_on = [kubernetes_namespace.osdfir]
}

# PVC (unchanged)
resource "kubernetes_persistent_volume_claim" "osdfirvolume" {
  metadata {
    name      = var.pvc_name
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name
    resources { requests = { storage = var.pvc_storage } }
  }
}

resource "null_resource" "helm_repo" {
  provisioner "local-exec" { command = "helm repo add osdfir-charts https://google.github.io/osdfir-infrastructure/" }
  provisioner "local-exec" { command = "helm repo update" }
}

# First deploy the main OSDFIR infrastructure
resource "helm_release" "osdfir" {
  name      = var.helm_release_name
  chart     = "osdfir-charts/osdfir-infrastructure"
  version   = var.osdfir_chart_version
  namespace = kubernetes_namespace.osdfir.metadata[0].name
  
  # Add this line to use your values file
  values = [file("${path.module}/../configs/osdfir-lab-values.yaml")]
  
  depends_on = [
    null_resource.helm_repo,
    kubernetes_namespace.osdfir,
    kubernetes_config_map.timesketch_configs
  ]
}
