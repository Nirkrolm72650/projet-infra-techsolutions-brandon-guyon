variable "pve_api_url" {
  description = "URL de l'API Proxmox"
  type        = string
}

variable "pve_token_id" {
  description = "Identifiant du Token API (user@realm!tokenid)"
  type        = string
}

variable "pve_token_secret" {
  description = "Secret du Token API"
  type        = string
  sensitive   = true
}

variable "target_node" {
  description = "Nom du nœud Proxmox de destination"
  type        = string
  default     = "PVE-Node-01"
}

variable "template_name" {
  description = "Nom ou ID du template Cloud-Init source"
  type        = string
  default     = "debian-13-template"
}

variable "ssh_public_key" {
  description = "Clé publique SSH injectée par Cloud-Init"
  type        = string
}