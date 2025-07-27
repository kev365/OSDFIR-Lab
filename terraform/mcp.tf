# Data source to read the Timesketch secret
data "kubernetes_secret" "timesketch" {
  metadata {
    name      = "osdfir-lab-timesketch-secret"
    namespace = "osdfir"
  }
}

resource "kubernetes_deployment" "timesketch_mcp_server" {
  depends_on = [helm_release.osdfir]

  metadata {
    name      = "timesketch-mcp-server"
    namespace = "osdfir"
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
          name              = "timesketch-mcp-server"
          image             = "timesketch-mcp-server:latest"
          image_pull_policy = "Never"
          command = ["uv", "run", "python", "src/main.py", "--mcp-host", "0.0.0.0", "--mcp-port", "8081"]

          port {
            container_port = 8081
          }

          # Timesketch connection environment variables
          env {
            name  = "TIMESKETCH_HOST"
            value = "osdfir-lab-timesketch"
          }
          env {
            name  = "TIMESKETCH_PORT"
            value = "5000"
          }
          env {
            name = "TIMESKETCH_USER"
            value_from {
              secret_key_ref {
                name = data.kubernetes_secret.timesketch.metadata[0].name
                key  = "timesketch-user"
              }
            }
          }
          env {
            name = "TIMESKETCH_PASSWORD"
            value_from {
              secret_key_ref {
                name = data.kubernetes_secret.timesketch.metadata[0].name
                key  = "timesketch-user"
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "timesketch_mcp_server" {
  metadata {
    name      = "timesketch-mcp-server"
    namespace = "osdfir"
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