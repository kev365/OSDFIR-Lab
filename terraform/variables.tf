# OSDFIR Chart Version
# This is the version of the osdfir-infrastructure Helm chart to deploy
# Release can be found here: https://github.com/google/osdfir-infrastructure/releases
variable "osdfir_chart_version" {
  description = "Version of the osdfir-infrastructure Helm chart to deploy"
  type        = string
  default     = "2.8.7"  # Only use the numerical part of the version
}


# MCP Server Deployments
# MCP (Model Context Protocol) servers provide AI tool interfaces to forensic platforms.
# Each MCP server connects to its respective service and exposes tools via SSE/HTTP.

# Timesketch MCP Server — queries Timesketch sketches, events, and timelines
# Source: https://github.com/timesketch/timesketch-mcp-server
variable "deploy_timesketch_mcp" {
  description = "Whether to deploy the Timesketch MCP Server"
  type        = bool
  default     = false  # false = disabled, true = enabled
}

# OpenRelik MCP Server — interacts with OpenRelik workflows and data
# Source: https://github.com/openrelik/openrelik-mcp-server
# Requires: API key created in OpenRelik UI (Settings > API Keys)
variable "deploy_openrelik_mcp" {
  description = "Whether to deploy the OpenRelik MCP Server"
  type        = bool
  default     = false  # false = disabled, true = enabled
}

# Yeti MCP Server — queries Yeti threat intelligence platform
# Source: https://github.com/yeti-platform/yeti-mcp
# Requires: API key created in Yeti UI
# Note: No official Docker image published yet — must be built and pushed to GHCR
variable "deploy_yeti_mcp" {
  description = "Whether to deploy the Yeti MCP Server"
  type        = bool
  default     = false  # false = disabled, true = enabled
}


# Ollama Configuration
# Control whether to deploy the Ollama server
variable "deploy_ollama" {
  description = "Whether to deploy the Ollama server"
  type        = bool
  default     = true
}

# Enable Vulkan GPU acceleration for Ollama (experimental)
# Vulkan is a cross-platform GPU API that can accelerate LLM inference.
# Only useful if the host has a GPU passed through to the Kubernetes node.
# In CPU-only environments (e.g., Minikube on laptop), leave this disabled.
# See: https://github.com/ollama/ollama/blob/main/docs/gpu.md
variable "enable_ollama_vulkan" {
  description = "Enable experimental Vulkan GPU acceleration for Ollama"
  type        = bool
  default     = false  # Set to true if GPU is available
}

# Set the AI Model to use with Ollama
variable "ai_model_name" {
  description = "Name of the AI model to use with Ollama"
  type        = string
  default     = "qwen2.5:0.5b"
}

# Set the maximum input tokens for the AI model
variable "ai_model_max_input_tokens" {
  description = "Maximum input tokens for the AI model"
  type        = number
  default     = 32768
}

# Set the URL for the Ollama server pod
variable "ai_model_server_url" {
  description = "URL for the Ollama server"
  type        = string
  default     = "http://ollama.osdfir.svc.cluster.local:11434"
}

variable "helm_timeout" {
  description = "Seconds Helm waits for resources to become ready"
  type        = number
  default     = 600
}


# OSDFIR-Lab Configuration
# Set the Kubernetes namespace for the OSDFIR deployment
variable "namespace" {
  description = "Kubernetes namespace for OSDFIR deployment"
  type        = string
  default     = "osdfir"
}

# Set the name of the PersistentVolumeClaim
variable "pvc_name" {
  description = "Name of the PersistentVolumeClaim"
  type        = string
  default     = "osdfirvolume"
}

# Set the name for the Helm release label
variable "helm_release_name" {
  description = "Name for the Helm release label"
  type        = string
  default     = "osdfir-lab"
}

# Set the storage size for the PVC
variable "pvc_storage" {
  description = "Storage size for the PVC"
  type        = string
  default     = "200Gi"
}

# Set the storage class to use for the PVC
variable "storage_class_name" {
  description = "Storage class to use for the PVC"
  type        = string
  default     = "standard"
}

# Set the GitHub repository name for the OSDFIR-Lab
variable "github_repository" {
  description = "GitHub repository name (e.g., 'kev365/osdfir-lab')"
  type        = string
  default     = "kev365/osdfir-lab"  # Use lowercase
}