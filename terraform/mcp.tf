# Data source to read the Timesketch secret
data "kubernetes_secret" "timesketch" {
  count = var.deploy_mcp_server ? 1 : 0
  metadata {
    name      = "osdfir-lab-timesketch-secret"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }
}

# Timesketch MCP Server deployment
resource "kubernetes_deployment" "timesketch_mcp_server" {
  count = var.deploy_mcp_server ? 1 : 0
  metadata {
    name      = "timesketch-mcp-server"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
    labels = {
      app = "timesketch-mcp-server"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "timesketch-mcp-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "timesketch-mcp-server"
        }
      }

      spec {
        container {
          
          image = "ghcr.io/${var.github_repository}/timesketch-mcp-server:latest"
          name  = "timesketch-mcp-server"
          image_pull_policy = "Always"  # or "IfNotPresent" if you prefer
          command = ["uv", "run", "python", "src/main.py", "--mcp-host", "0.0.0.0", "--mcp-port", "8081"]

          port {
            container_port = 8081
          }

          env {
            name  = "TIMESKETCH_HOST"
            value = "osdfir-lab-timesketch"
          }

          env {
            name  = "TIMESKETCH_PORT"
            value = "443"
          }

          env {
            name  = "TIMESKETCH_USERNAME"
            value_from {
              secret_key_ref {
                name = "osdfir-lab-timesketch-secret"
                key  = "username"
              }
            }
          }

          env {
            name  = "TIMESKETCH_PASSWORD"
            value_from {
              secret_key_ref {
                name = "osdfir-lab-timesketch-secret"
                key  = "password"
              }
            }
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.osdfir
  ]
}

# Service for the MCP Server
resource "kubernetes_service" "timesketch_mcp_server" {
  count = var.deploy_mcp_server ? 1 : 0
  metadata {
    name      = "timesketch-mcp-server"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }

  spec {
    selector = {
      app = "timesketch-mcp-server"
    }

    port {
      port        = 8081
      target_port = 8081
    }

    type = "ClusterIP"
  }
}