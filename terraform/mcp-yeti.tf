# Yeti MCP Server deployment
# Source: https://github.com/yeti-platform/yeti-mcp
#
# Note: No official Docker image is published by the Yeti project yet.
# You must build and push the image yourself. Example:
#   git clone https://github.com/yeti-platform/yeti-mcp.git
#   cd yeti-mcp
#   docker build -t ghcr.io/<your-org>/yeti-mcp-server:latest .
#   docker push ghcr.io/<your-org>/yeti-mcp-server:latest
#
# Prerequisites:
#   1. Create an API key in Yeti UI (Admin > API Keys)
#   2. Create a Kubernetes secret with the API key:
#      kubectl create secret generic yeti-mcp-secret \
#        --from-literal=api-key=<YOUR_API_KEY> -n osdfir

resource "kubernetes_deployment" "yeti_mcp_server" {
  count = var.deploy_yeti_mcp ? 1 : 0

  metadata {
    name      = "yeti-mcp-server"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
    labels = {
      app = "yeti-mcp-server"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "yeti-mcp-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "yeti-mcp-server"
        }
      }

      spec {
        container {
          name              = "yeti-mcp-server"
          image             = "ghcr.io/${split("/", var.github_repository)[0]}/yeti-mcp-server:latest"
          image_pull_policy = "IfNotPresent"
          command           = ["uv", "run", "python", "-m", "src.server", "--mcp-host", "0.0.0.0", "--mcp-port", "8082"]

          port {
            container_port = 8082
          }

          env {
            name  = "YETI_ENDPOINT"
            value = "http://${var.helm_release_name}-yeti-api:80/api/v2"
          }

          env {
            name = "YETI_API_KEY"
            value_from {
              secret_key_ref {
                name     = "yeti-mcp-secret"
                key      = "api-key"
                optional = true
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

resource "kubernetes_service" "yeti_mcp_server" {
  count = var.deploy_yeti_mcp ? 1 : 0

  metadata {
    name      = "yeti-mcp-server"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }

  spec {
    selector = {
      app = "yeti-mcp-server"
    }

    port {
      port        = 8082
      target_port = 8082
    }

    type = "ClusterIP"
  }
}
