# Projet : Infrastructure Virtualisée pour TechSolutions Inc.
### Groupe : Brandon, Antonin, David

## 1. Vue d'ensemble de l'architecture

![Schéma d'architecture](/Screenshots/schéma-infra-virtualisée.drawio.png)

L'infrastructure repose sur six machines virtuelles réparties sur trois nœuds Proxmox (`pve-node-01`, `pve-node-02`, `pve-node-03`) :

| Machine | Rôle | Nœud Proxmox | IP Admin (`vmbr0`) | IP Prod (`prod` SDN) | Stockage VM |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **db-client-01** | Base PostgreSQL primaire | pve-node-01 | `192.168.100.61` | `172.16.0.11` | Pool Ceph RBD |
| **db-client-02** | Base PostgreSQL secondaire | pve-node-02 | `192.168.100.62` | `172.16.0.12` | Pool Ceph RBD |
| **api-internal-01** | API interne Flask | pve-node-03 | `192.168.100.63` | `172.16.0.21` | Pool Ceph RBD |
| **api-internal-02** | API interne Flask | pve-node-0 | `192.168.100.64` | `172.16.0.22` | Pool Ceph RBD |
| **web-01** | Nginx & GlusterFS | pve-node-02 | `192.168.100.65` | `172.16.0.31` | Local LVM |
| **web-02** | Nginx & GlusterFS | pve-node-03 | `192.168.100.66` | `172.16.0.32` | Local LVM |

### Topologie réseau & stockage
* **Réseau d'administration :** `192.168.100.0/24` via le pont `vmbr0`, utilisé pour le provisioning SSH depuis le bastion.
* **Réseau de production :** `172.16.0.0/24` encapsulé dans un pont Proxmox SDN VXLAN nommé `prod` traversant les trois hyperviseurs physiques.
* **Haute disponibilité Web :** Volume miroir **GlusterFS Replica 2** synchronisé sur le réseau de production et monté localement sur `/var/www/html`.