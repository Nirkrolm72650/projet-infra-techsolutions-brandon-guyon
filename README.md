# Projet : Infrastructure Virtualisée pour TechSolutions Inc.
### Groupe : Brandon, Antonin, David (bad)

---

## 1. Vue d'ensemble de l'architecture

![Schéma d'architecture](/Screenshots/schéma-infra-virtualisée.png)

L'infrastructure s'articule autour d'un cluster Proxmox VE de trois nœuds physiques (`pve-node-01`, `pve-node-02`, `pve-node-03`) interconnectés à une baie de stockage distribuée et protégés par un pare-feu central DynFi.

### Inventaire des machines virtuelles (Services métiers)

| Machine | Rôle | Nœud Proxmox | IP Admin (`vmbr0`) | IP Prod (`prod` SDN) | Stockage VM |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **db-client-01** | Base PostgreSQL primaire | pve-node-01 | `192.168.100.61` | `172.16.0.11` | Pool Ceph RBD (`ceph-vm-pool`) |
| **db-client-02** | Base PostgreSQL secondaire | pve-node-02 | `192.168.100.62` | `172.16.0.12` | Pool Ceph RBD (`ceph-vm-pool`) |
| **api-internal-01** | API interne Flask | pve-node-03 | `192.168.100.63` | `172.16.0.21` | Pool Ceph RBD (`ceph-vm-pool`) |
| **api-internal-02** | API interne Flask | pve-node-01 | `192.168.100.64` | `172.16.0.22` | Pool Ceph RBD (`ceph-vm-pool`) |
| **web-01** | Nginx & GlusterFS | pve-node-02 | `192.168.100.65` | `172.16.0.31` | GlusterFS / local-lvm |
| **web-02** | Nginx & GlusterFS | pve-node-03 | `192.168.100.66` | `172.16.0.32` | GlusterFS / local-lvm |

### Conteneurs d'infrastructure (LXC)

| Instance | Rôle | Nœud Proxmox | IP Réseau Admin | Particularités |
| :--- | :--- | :--- | :--- | :--- |
| **bastion-01** (CT 200) | Passerelle d'accès SSH & Apache Guacamole | pve-node-01 | `192.168.100.50` | Docker Compose activé (`nesting=1`), disque 30 Go |
| **monitoring-01** (CT 201) | Collecte métriques et tableaux de bord | pve-node-01 | `192.168.100.51` | Prometheus, Node Exporter et Grafana |

---

## 2. Topologie Réseau et Stockage

### Segmentation Réseau
* **Réseau d'administration (`vmbr0`) :** `192.168.100.0/24`. Utilisé pour la gestion des hyperviseurs, le provisioning Ansible/Terraform et les connexions SSH.
* **Réseau de production (SDN VXLAN `prod`) :** `172.16.0.0/24`. Zone étanche pour les échanges applicatifs entre le front-end web, les APIs Flask et les bases PostgreSQL.
* **Réseau de stockage interne :** `10.0.0.0/24`. Réseau dédié au trafic de synchronisation du cluster Ceph.
* **Pare-feu DynFi :** Passerelle par défaut (`192.168.100.1`) exposant les interfaces web via translation d'adresse (Port Forwarding NAT) sur l'IP WAN `10.20.10.18`.
* **Optimisation MTU :** L'ensemble des interfaces physiques et ponts (`nic0`, `vmbr0`) est calibré à une **MTU de 1360** afin de prévenir les ruptures de flux vers les réseaux imbriqués (*PMTU Black Hole*).

### Stratégie de Stockage Distribué
* **Ceph RBD (`ceph-vm-pool`) :** Stockage en mode bloc distribué sur les disques OSD des trois nœuds Proxmox, garantissant la haute disponibilité sans point unique de défaillance (*SPOF*).
* **GlusterFS Replica 2 :** Réplication bidirectionnelle en temps réel du dossier `/var/www/html` entre `web-01` et `web-02` à travers le réseau de production.

---

## 3. Sécurité, Passerelle Bastion et Cloisonnement RBAC

L'accès à l'infrastructure applique le principe de moindre privilège selon la matrice des habilitations :

### Passerelle Web Apache Guacamole
Déployée sur `bastion-01` via un environnement conteneurisé (`guacamole`, `guacd`, `guacamole-db`), l'interface permet d'administrer les machines via un navigateur web sans client lourd :
* **Isolation cryptographique des clés :** Chaque compte Guacamole est associé à une connexion distincte exploitant sa propre paire de clés asymétriques Ed25519 (`/home/<user>/.ssh/id_ed25519`).
* **Verrouillage système :** Le bastion est configuré avec `PasswordAuthentication no`. Les outils d'automatisation (`/usr/bin/terraform` et l'environnement virtuel Python) sont strictement restreints en droits `chmod 750` aux administrateurs.

### Matrice synthétique des accès

| Utilisateur / Profil | SSH Bastion | SSH Hyperviseurs | Console Web Proxmox | Droits Grafana |
| :--- | :---: | :---: | :---: | :---: |
| **bad** (Admin Senior / Brandon, Antonin, David) | ✅ (sudo) | ✅ (`root`) | `Administrator` (complet) | `Admin` |
| **Emma Lambert** (Admin Sys) | ✅ (sudo) | ✅ (`root`) | `Administrator` (complet) | `Editor` / `Admin` |
| **Antoine & Cécile** (DevOps) | ✅ (sans sudo) | ❌ | ❌ | `Editor` |
| **Nicolas Petit** (Support N2) | ✅ (lecture seule) | ❌ | ❌ | `Viewer` |
| **Laura Fernandez** (Support N1) | ❌ | ❌ | ❌ | `Viewer` |
| **Lucas Moreau** (Stagiaire) | ❌ | ❌ | `PVEAuditor` (lecture seule) | ❌ |

---

## 4. Politique de Sauvegarde et Reprise d'Activité (PBS)

Les sauvegardes sont centralisées sur **Proxmox Backup Server** (`10.20.10.30`), sur le datastore distant `BackupPoolNas` :
* **Mode de sauvegarde :** Snapshot à chaud avec exclusion des fichiers temporaires (`vzdump`).
* **Déduplication et chiffrement :** Sauvegardes incrémentales optimisées par découpage en blocs (*chunks*) SHA-256 avec suivi des modifications via *dirty bitmaps*.
* **Vérification d'intégrité (*Verify Jobs*) :** Planification automatisée quotidienne du contrôle des manifestes pour garantir la restaurabilité sans corruption de données.

---

## 5. Automatisation et Exploitation

* **Provisioning d'infrastructure :** Fichiers de configuration Terraform déclarant les ressources d'orchestration depuis le bastion.
* **Cycle de vie des machines :** Scripts d'audit et de maintenance programmée (nettoyage automatisé et suivi des états) s'appuyant sur la bibliothèque Python `proxmoxer`.
* **Supervision temps réel :** Tableaux de bord de performance système sous Grafana exploitant les métriques remontées par les agents Prometheus Node Exporter.

---

## 6. URLs et Points d'Accès

* **Interface Proxmox VE :** `https://10.20.10.18:8006` (Nœud 1), `:8009` (Nœud 2), `:8008` (Nœud 3)
* **Passerelle Apache Guacamole :** `http://10.20.10.18:8080/guacamole/` 
* **Supervision Grafana :** `http://10.20.10.18:3000/`
* **Proxmox Backup Server :** `https://10.20.10.30:8007/`

### 7. Identifiants d'accès à la passerelle Apache Guacamole

L'accès s'effectue sur `http://10.20.10.18:8080/guacamole/` via les comptes suivants :

| Identifiant | Mot de passe | Rôle | Périmètre et connexions autorisées |
| :--- | :--- | :--- | :--- |
| **`guacadmin`** | `guacadmin` | Administrateur Guacamole | Gestion globale de la plateforme, création/édition des connexions et comptes. |
| **`bad`** | `bad12345` | Admin Senior | `Bastion - BAD`, `pve-node-01`, `pve-node-02`, `pve-node-03`. |
| **`emma`** | `bad12345` | Admin Système | `Bastion - Emma`, `pve-node-01`, `pve-node-02`, `pve-node-03`. |
| **`antoine`** | `bad12345` | DevOps | `Bastion - Antoine` uniquement (droits sudo limités à Terraform et Python). Se connecte directement au bastion avec son nom d'utilisateur|
| **`cecile`** | `bad12345` | DevOps | `Bastion - Cécile` uniquement (droits sudo limités à Terraform et Python). Se connecte directement au bastion avec son nom d'utilisateur |

*Note : Les profils Lucas (stagiaire), Nicolas et Laura (support) ne disposent d'aucun compte Guacamole, conformément à la politique de restriction d'accès.*