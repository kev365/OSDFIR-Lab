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