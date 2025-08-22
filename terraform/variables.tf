# OSDFIR Chart Version
# This is the version of the osdfir-infrastructure Helm chart to deploy
# Release can be found here: https://github.com/google/osdfir-infrastructure/releases
variable "osdfir_chart_version" {
  description = "Version of the osdfir-infrastructure Helm chart to deploy"
  type        = string
  default     = "2.4.3"  # Only use the numerical part of the version
}


# Timesketch MCP Server
# Control whether to deploy the Timesketch MCP Server
variable "deploy_mcp_server" {
  description = "Whether to deploy the Timesketch MCP Server"
  type        = bool
  default     = false  # false = disabled, true = enabled
}


# Ollama Configuration
# Control whether to deploy the Ollama server
variable "deploy_ollama" {
  description = "Whether to deploy the Ollama server"
  type        = bool
  default     = true  # false = disabled, true = enabled
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