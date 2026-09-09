# ==============================================================================
# DÉFINITION DES VARIABLES LOCALES (VMs DU CLUSTER)
# ==============================================================================

locals {
  # Machines déployées sur le stockage partagé Ceph
  ceph_vms = {
    "db-client-01" = {
      vmid        = 111
      target_node = "pve-node-01"
      ip_admin    = "192.168.100.61"
      ip_prod     = "172.16.0.11"
      cores       = 4
      memory      = 4096
      disk        = 30
    }
    "db-client-02" = {
      vmid        = 112
      target_node = "pve-node-02"
      ip_admin    = "192.168.100.62"
      ip_prod     = "172.16.0.12"
      cores       = 4
      memory      = 4096
      disk        = 30
    }
    "api-internal-01" = {
      vmid        = 113
      target_node = "pve-node-03"
      ip_admin    = "192.168.100.63"
      ip_prod     = "172.16.0.21"
      cores       = 2
      memory      = 2048
      disk        = 20
    }
    "api-internal-02" = {
      vmid        = 114
      target_node = "pve-node-01"
      ip_admin    = "192.168.100.64"
      ip_prod     = "172.16.0.22"
      cores       = 2
      memory      = 2048
      disk        = 20
    }
  }

  # Machines déployées sur le stockage local (local-lvm) des nœuds 2 et 3
  web_vms = {
    "web-01" = {
      vmid        = 121
      target_node = "pve-node-02"
      ip_admin    = "192.168.100.65"
      ip_prod     = "172.16.0.31"
      cores       = 2
      memory      = 2048
      disk        = 20
    }
    "web-02" = {
      vmid        = 122
      target_node = "pve-node-03"
      ip_admin    = "192.168.100.66"
      ip_prod     = "172.16.0.32"
      cores       = 2
      memory      = 2048
      disk        = 20
    }
  }
}


# ==============================================================================
# 1. RESSOURCES : MACHINES SUR CEPH (db-client & api-internal)
# ==============================================================================

resource "proxmox_vm_qemu" "ceph_nodes" {
  for_each    = local.ceph_vms
  vmid        = each.value.vmid
  name        = each.key
  target_node = each.value.target_node
  clone       = var.template_name

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  memory = each.value.memory
  scsihw = "virtio-scsi-pci"
  boot   = "order=scsi0"

  vga {
    type = "serial0"
  }

  serial {
    id   = 0
    type = "socket"
  }

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = "ceph-vm-pool"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size      = each.value.disk
          storage   = "ceph-vm-pool"
          replicate = false
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  network {
    id     = 1
    model  = "virtio"
    bridge = "prod"
  }

  os_type   = "cloud-init"
  ipconfig0 = "ip=${each.value.ip_admin}/24,gw=192.168.100.1"
  ipconfig1 = "ip=${each.value.ip_prod}/24"
  ciuser    = "debian"
  sshkeys   = var.ssh_public_key
  agent     = 1
}

# ==============================================================================
# 2. RESSOURCES : MACHINES SUR LOCAL-LVM (web-01 & web-02)
# ==============================================================================

resource "proxmox_vm_qemu" "web_nodes" {
  for_each    = local.web_vms
  vmid        = each.value.vmid
  name        = each.key
  target_node = each.value.target_node
  clone       = var.template_name
  full_clone  = true

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  memory = each.value.memory
  scsihw = "virtio-scsi-pci"
  boot   = "order=scsi0"

  vga {
    type = "serial0"
  }

  serial {
    id   = 0
    type = "socket"
  }

  disks {
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size      = each.value.disk
          storage   = "local-lvm"
          replicate = false
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  network {
    id     = 1
    model  = "virtio"
    bridge = "prod"
  }

  os_type   = "cloud-init"
  ipconfig0 = "ip=${each.value.ip_admin}/24,gw=192.168.100.1"
  ipconfig1 = "ip=${each.value.ip_prod}/24"
  ciuser    = "debian"
  sshkeys   = var.ssh_public_key
  agent     = 1
}
