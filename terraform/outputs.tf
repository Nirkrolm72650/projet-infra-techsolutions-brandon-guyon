output "ceph_vms_ips" {
  description = "Adresses IP des machines Ceph"
  value       = { for k, vm in proxmox_vm_qemu.ceph_nodes : k => vm.default_ipv4_address }
}

output "web_vms_ips" {
  description = "Adresses IP des serveurs Web"
  value       = { for k, vm in proxmox_vm_qemu.web_nodes : k => vm.default_ipv4_address }
}