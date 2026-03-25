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
  count              = var.deploy_ollama ? 1 : 0
  wait_for_rollout   = false  # Model pull can take minutes; don't block Terraform

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
          args = [replace(<<-EOT
set -e
MODEL="${var.ai_model_name}"
MODEL_DIR=$(printf '%s' "$MODEL" | tr ':' '/')
MODEL_PATH="/root/.ollama/models/manifests/registry.ollama.ai/library/$MODEL_DIR"

echo "Checking if $MODEL model already exists..."
if [ -f "$MODEL_PATH" ]; then
  echo "Model $MODEL already exists, skipping download"
  exit 0
fi

echo "Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!

echo "Waiting for Ollama to be ready..."
for i in $(seq 1 30); do
  if ollama list >/dev/null 2>&1; then
    echo "Ollama service is ready!"
    break
  fi
  echo "Waiting for Ollama... (attempt $i/30)"
  sleep 5
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Ollama service did not become ready"
    kill $OLLAMA_PID 2>/dev/null || true
    exit 1
  fi
done

echo "Pulling model $MODEL..."
ollama pull "$MODEL"

echo "Model pull completed, stopping init service..."
kill $OLLAMA_PID 2>/dev/null || true
wait $OLLAMA_PID 2>/dev/null || true
echo "Init container done."
          EOT
          , "\r", "")]
          
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

          env {
            name  = "OLLAMA_VULKAN"
            value = var.enable_ollama_vulkan ? "1" : "0"
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
            timeout_seconds       = 10
          }

          liveness_probe {
            http_get {
              path = "/api/tags"
              port = 11434
            }
            initial_delay_seconds = 60
            period_seconds        = 30
            timeout_seconds       = 10
            failure_threshold     = 5
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

# Patch the OpenRelik API deployment with LLM environment variables.
# The OpenRelik Helm chart does not natively support LLM config on the API pod,
# but openrelik-ai-common reads these env vars to discover available LLM providers.
# Without these, the OpenRelik UI shows "no LLMs configured".
resource "null_resource" "openrelik_api_llm_env" {
  count = var.deploy_ollama ? 1 : 0

  triggers = {
    model_name = var.ai_model_name
    server_url = var.ai_model_server_url
  }

  provisioner "local-exec" {
    command = "kubectl set env deployment/${var.helm_release_name}-openrelik-api -n ${var.namespace} OLLAMA_SERVER_URL=${var.ai_model_server_url} OLLAMA_DEFAULT_MODEL=${var.ai_model_name}"
  }

  depends_on = [
    helm_release.osdfir,
    kubernetes_deployment.ollama
  ]
}

# Workaround: The OpenRelik Helm chart (2.8.4) has a YAML indentation bug in the
# worker-deployment template where secretKeyRef is not nested under valueFrom:,
# causing TIMESKETCH_PASSWORD to be empty. This patches the worker with the
# correct password from the Timesketch secret.
resource "null_resource" "openrelik_timesketch_worker_fix" {
  triggers = {
    helm_release = var.osdfir_chart_version
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-NoProfile", "-Command"]
    command     = "$pw = kubectl get secret ${var.helm_release_name}-timesketch-secret -n ${var.namespace} -o jsonpath='{.data.timesketch-user}'; $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pw)); kubectl set env deployment/${var.helm_release_name}-openrelik-worker-timesketch -n ${var.namespace} TIMESKETCH_PASSWORD=$decoded"
  }

  depends_on = [
    helm_release.osdfir
  ]
}