# OpenRelik MCP Server deployment
# Source: https://github.com/openrelik/openrelik-mcp-server
#
# Prerequisites:
#   1. Create a user in OpenRelik UI (e.g., "mcp-agent")
#   2. Generate an API key under that user's settings
#   3. Create a Kubernetes secret with the API key:
#      kubectl create secret generic openrelik-mcp-secret \
#        --from-literal=api-key=<YOUR_API_KEY> -n osdfir

resource "kubernetes_deployment" "openrelik_mcp_server" {
  count = var.deploy_openrelik_mcp ? 1 : 0

  metadata {
    name      = "openrelik-mcp-server"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
    labels = {
      app = "openrelik-mcp-server"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "openrelik-mcp-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "openrelik-mcp-server"
        }
      }

      spec {
        container {
          name              = "openrelik-mcp-server"
          image             = "ghcr.io/openrelik/openrelik-mcp-server:latest"
          image_pull_policy = "Always"

          port {
            container_port = 7070
          }

          env {
            name  = "OPENRELIK_API_URL"
            value = "http://${var.helm_release_name}-openrelik-api:8710"
          }

          env {
            name = "OPENRELIK_API_KEY"
            value_from {
              secret_key_ref {
                name     = "openrelik-mcp-secret"
                key      = "api-key"
                optional = true
              }
            }
          }

          env {
            name  = "MCP_TRANSPORT"
            value = "http"
          }

          env {
            name  = "MCP_HTTP_HOST"
            value = "0.0.0.0"
          }

          env {
            name  = "MCP_HTTP_PORT"
            value = "7070"
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

resource "kubernetes_service" "openrelik_mcp_server" {
  count = var.deploy_openrelik_mcp ? 1 : 0

  metadata {
    name      = "openrelik-mcp-server"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }

  spec {
    selector = {
      app = "openrelik-mcp-server"
    }

    port {
      port        = 7070
      target_port = 7070
    }

    type = "ClusterIP"
  }
}
