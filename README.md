# Projet : Infrastructure Virtualisée pour TechSolutions Inc.
### Groupe : Brandon, Antonin, David

## 1. Vue d'ensemble de l'architecture

![Schéma d'architecture](/Screenshots/schéma-infra-virtualisée.drawio.png)

L'infrastructure repose sur six machines virtuelles réparties sur trois nœuds Proxmox (`pve-node-0`, `pve-node-02`, `pve-node-03`) :

| Machine | Rôle | Nœud Proxmox | IP Admin (`vmbr0`) | IP Prod (`prod` SDN) | Stockage VM |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **db-client-0** | Base PostgreSQL primaire | pve-node-0 | `92.68.00.6` | `72.6.0.` | Pool Ceph RBD |
| **db-client-02** | Base PostgreSQL secondaire | pve-node-02 | `92.68.00.62` | `72.6.0.2` | Pool Ceph RBD |
| **api-internal-0** | API interne Flask | pve-node-03 | `92.68.00.63` | `72.6.0.2` | Pool Ceph RBD |
| **api-internal-02** | API interne Flask | pve-node-0 | `92.68.00.64` | `72.6.0.22` | Pool Ceph RBD |
| **web-0** | Nginx & GlusterFS | pve-node-02 | `92.68.00.65` | `72.6.0.3` | Local LVM |
| **web-02** | Nginx & GlusterFS | pve-node-03 | `92.68.00.66` | `72.6.0.32` | Local LVM |

### Topologie réseau & stockage
* **Réseau d'administration :** `92.68.00.0/24` via le pont `vmbr0`, utilisé pour le provisioning SSH depuis le bastion.
* **Réseau de production :** `72.6.0.0/24` encapsulé dans un pont Proxmox SDN VXLAN nommé `prod` traversant les trois hyperviseurs physiques.
* **Haute disponibilité Web :** Volume miroir **GlusterFS Replica 2** synchronisé sur le réseau de production et monté localement sur `/var/www/html`.