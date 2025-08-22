# Control whether to deploy Ollama
variable "deploy_ollama" {
  description = "Whether to deploy the Ollama server"
  type        = bool
  default     = true  # false = disabled, true = enabled
}

# Read AI configuration from values file
locals {
  values_yaml = yamldecode(file("${path.module}/../configs/osdfir-lab-values.yaml"))
  ai_config = local.values_yaml.ai
}

# Ollama deployment
resource "kubernetes_persistent_volume_claim" "ollama_cache" {
  count = var.deploy_ollama ? 1 : 0
  
  metadata {
    name      = "ollama-cache"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }
  
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name
    resources {
      requests = {
        storage = "15Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "ollama" {
  count = var.deploy_ollama ? 1 : 0
  
  metadata {
    name      = "ollama"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }
  
  spec {
    replicas = 1
    
    selector {
      match_labels = {
        app = "ollama"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "ollama"
        }
      }
      
      spec {
        init_container {
          name            = "model-puller"
          image           = "ollama/ollama:latest"
          image_pull_policy = "IfNotPresent"
          
          command = ["/bin/bash", "-c"]
          args = [<<-EOT
            echo "Checking if qwen2.5:0.5b model already exists..."
            if [ -f /root/.ollama/models/manifests/registry.ollama.ai/library/qwen2.5/0.5b ]; then
              echo "Model qwen2.5:0.5b already exists, skipping download"
              exit 0
            fi
            
            echo "Starting Ollama service..."
            ollama serve &
            OLLAMA_PID=$!
            
            echo "Waiting for Ollama to be ready..."
            max_attempts=30
            attempt=0
            while [ $attempt -lt $max_attempts ]; do
              if ollama list >/dev/null 2>&1; then
                echo "Ollama service is ready!"
                break
              fi
              echo "Waiting for Ollama... (attempt $((attempt + 1))/$max_attempts)"
              sleep 5
              attempt=$((attempt + 1))
            done
            
            if [ $attempt -eq $max_attempts ]; then
              echo "ERROR: Ollama service did not become ready after $((max_attempts * 5)) seconds"
              kill $OLLAMA_PID 2>/dev/null || true
              exit 1
            fi
            
            echo "Pulling model qwen2.5:0.5b..."
            ollama pull qwen2.5:0.5b
            
            echo "Model pull completed, stopping init service..."
            kill $OLLAMA_PID
            wait $OLLAMA_PID
          EOT
          ]
          
          volume_mount {
            name       = "ollama-cache"
            mount_path = "/root/.ollama"
          }
          
          resources {
            requests = {
              memory = "2Gi"
              cpu    = "1"
            }
            limits = {
              memory = "4Gi"
              cpu    = "2"
            }
          }
        }
        
        container {
          name            = "ollama"
          image           = "ollama/ollama:latest"
          image_pull_policy = "IfNotPresent"
          
          port {
            container_port = 11434
          }
          
          env {
            name  = "OLLAMA_HOST"
            value = "0.0.0.0:11434"
          }
          
          env {
            name  = "OLLAMA_NUM_PARALLEL"
            value = "1"
          }
          
          env {
            name  = "OLLAMA_KEEP_ALIVE"
            value = "5m"
          }
          
          volume_mount {
            name       = "ollama-cache"
            mount_path = "/root/.ollama"
          }
          
          readiness_probe {
            http_get {
              path = "/api/tags"
              port = 11434
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          
          liveness_probe {
            http_get {
              path = "/api/tags"
              port = 11434
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }
          
          resources {
            requests = {
              memory = "4Gi"
              cpu    = "2"
            }
            limits = {
              memory = "8Gi"
              cpu    = "3"
            }
          }
        }
        
        volume {
          name = "ollama-cache"
          persistent_volume_claim {
            claim_name = "ollama-cache"
          }
        }
      }
    }
  }
  
  depends_on = [
    kubernetes_persistent_volume_claim.ollama_cache
  ]
}

resource "kubernetes_service" "ollama" {
  count = var.deploy_ollama ? 1 : 0
  
  metadata {
    name      = "ollama"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }
  
  spec {
    selector = {
      app = "ollama"
    }
    
    port {
      port        = 11434
      target_port = 11434
    }
    
    type = "ClusterIP"
  }
}

resource "kubernetes_config_map" "ollama_models_config" {
  count = var.deploy_ollama ? 1 : 0
  
  metadata {
    name      = "ollama-models-config"
    namespace = kubernetes_namespace.osdfir.metadata[0].name
  }
  
  data = {
    "available-models.json" = jsonencode({
      models = [
        {
          name = var.ai_model_name
          display_name = title(var.ai_model_name)
          description = "${var.ai_model_name} model for text generation and analysis"
          context_length = var.ai_model_max_input_tokens
          capabilities = ["text-generation", "analysis", "forensics"]
        }
      ]
    })
  }
}
