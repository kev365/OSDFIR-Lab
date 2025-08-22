variable "namespace" {
  description = "Kubernetes namespace for OSDFIR deployment"
  type        = string
  default     = "osdfir"
}

variable "pvc_name" {
  description = "Name of the PersistentVolumeClaim"
  type        = string
  default     = "osdfirvolume"
}

variable "pvc_storage" {
  description = "Storage size for the PVC"
  type        = string
  default     = "200Gi"
}

variable "storage_class_name" {
  description = "Storage class to use for the PVC"
  type        = string
  default     = "standard"
}

variable "helm_release_name" {
  description = "Name for the Helm release of OSDFIR Infrastructure"
  type        = string
  default     = "osdfir-lab"
}

variable "github_repository" {
  description = "GitHub repository name (e.g., 'kev365/osdfir-lab')"
  type        = string
  default     = "kev365/osdfir-lab"  # Use lowercase
}

# AI Model Configuration
variable "ai_model_name" {
  description = "Name of the AI model to use with Ollama"
  type        = string
  default     = "qwen2.5:0.5b"
}

variable "ai_model_max_input_tokens" {
  description = "Maximum input tokens for the AI model"
  type        = number
  default     = 32768
}

variable "ai_model_server_url" {
  description = "URL for the Ollama server"
  type        = string
  default     = "http://ollama.osdfir.svc.cluster.local:11434"
}

# Control whether to deploy the Timesketch MCP Server
variable "deploy_mcp_server" {
  description = "Whether to deploy the Timesketch MCP Server"
  type        = bool
  default     = false  # false = disabled, true = enabled
}