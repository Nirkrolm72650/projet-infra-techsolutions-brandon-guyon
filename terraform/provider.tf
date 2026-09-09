terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc10"
    }
  }
}

provider "proxmox" {
  pm_api_url                 = var.pve_api_url
  pm_api_token_id            = var.pve_token_id
  pm_api_token_secret        = var.pve_token_secret
  pm_tls_insecure            = true
  pm_minimum_permission_check = false
  pm_timeout      = 300
}