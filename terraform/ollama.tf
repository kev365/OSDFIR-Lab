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
          # Using a simpler script with proper escape sequences
          args = ["#!/bin/bash\nset -e\necho 'Checking if model exists...'\nif [ -f /root/.ollama/models/manifests/registry.ollama.ai/library/qwen2.5/0.5b ]; then\n  echo 'Model already exists, skipping download'\n  exit 0\nfi\necho 'Starting Ollama service...'\nollama serve &\nOLLAMA_PID=$!\necho 'Waiting for Ollama to be ready...'\nfor i in $(seq 1 30); do\n  if ollama list >/dev/null 2>&1; then\n    echo 'Ollama service is ready!'\n    break\n  fi\n  echo \"Waiting for Ollama... (attempt $i/30)\"\n  sleep 5\n  if [ $i -eq 30 ]; then\n    echo 'ERROR: Ollama service did not become ready'\n    kill $OLLAMA_PID 2>/dev/null || true\n    exit 1\n  fi\ndone\necho 'Pulling model qwen2.5:0.5b...'\nollama pull qwen2.5:0.5b\necho 'Model pull completed, stopping init service...'\nkill $OLLAMA_PID\nwait $OLLAMA_PID"]
          
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