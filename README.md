# Projet : Infrastructure Virtualisée pour TechSolutions Inc.
## Groupe : Brandon, Antonin, David (bad)

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

## 8. Guide de déploiement et automatisation

L'ensemble des opérations d'automatisation s'exécute depuis le conteneur `bastion-01` avec un profil habilité (`bad`, `emma`, `antoine` ou `cecile`).

### Étape 1 : Configuration des variables Terraform

Avant d'exécuter Terraform, copier le modèle de variables et renseigner les accès API Proxmox :

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```
- Adapter les paramètres selon l'environnement :

- pve_api_url : URL d'accès API au cluster (ex. https://192.168.100.11:8006/api2/json).

- ;pve_token_id : Identifiant du jeton API (ex. terraform-prov@pve!terraform-token).

- pve_token_secret : Secret du jeton généré sur Proxmox VE.

- ssh_public_key : Clé publique SSH du bastion (contenu de ~/.ssh/id_ed25519.pub).

### Étape 2 : Déploiement automatisé global
Pour instancier les machines virtuelles et exécuter les playbooks de configuration applicative en une seule passe, lancer le script global à la racine du dépôt :
```bash
chmod +x scripts/deploy-all.sh
./scripts/deploy-all.sh
```

### Étape 3 : Résolution d'incidents Ansible (Serveurs web-01 et web-02)
Si le déploiement Ansible rencontre un blocage sur les nœuds web (notamment lors de l'initialisation du replica GlusterFS ou du rechargement de Nginx) :

1. Se positionner directement dans le répertoire Ansible :
```bash
cd ansible-cluster/
```

2. Vérifier la joignabilité SSH des serveurs web :
```bash
ansible -i hosts.ini web -m ping
```

3. Relancer spécifiquement le playbook dédié aux serveurs web :
```bash
ansible-playbook -i hosts.ini web.yml
```

### Étape 4 : Décommissionnement des VMs
Pour purger proprement une plage de machines de test après validation :
```bash
python3 scripts/destroy_all_vms.py --start 150 --end 152 --yes
```

### 9. Commandes
1. Ping toutes les vms
```bash
ansible -i hosts.ini all -m ping
```

2. Ping un groupe de vm
```bash
ansible -i hosts.ini db -m ping     # Uniquement les bases PostgreSQL
ansible -i hosts.ini api -m ping    # Uniquement les serveurs Flask
ansible -i hosts.ini web -m ping    # Uniquement les serveurs Nginx/GlusterFS
```

3. Relancer la configuration sur toutes les VMs
```bash
ansible-playbook -i hosts.ini master.yml
```

4. Rentrer dans le bastion (`pve-node-01`)
```bash
pct enter 200
```

1. Rentrer dans la conteneur monitoring (`pve-node-01`)
```bash
pct enter 201
```


### Dépannage GlusterFS : Désynchronisation du cluster (`Peer Rejected` / `Staging failed`)

![Erreur-ansible-vm-web](/Screenshots/ansible-web-vms.png)

#### Symptômes rencontrés
* Lors de l'exécution du playbook `web.yml`, la tâche de vérification du cluster échoue avec le statut `State: Peer Rejected (Connected)`.
* La création du volume répliqué renvoie :  
  `volume create: web_vol: failed: Staging failed on 172.16.0.32. Error: Host 172.16.0.31 is not in 'Peer in Cluster' state`.

#### Cause
Ce problème survient lorsqu'un nœud web (`web-02`) est redéployé via Terraform. La nouvelle machine génère un nouvel UUID GlusterFS, tandis que `web-01` conserve l'ancien UUID associé à l'IP `172.16.0.32` dans `/var/lib/glusterd/peers/` et dans les fichiers de définition de volume. Le rejet mutuel bloque la formation du cluster et le montage de `/var/www/html`.

#### Procédure de résolution

1. **Purger l'état résiduel et réinitialiser les démons :**  
   Exécuter ces commandes successivement sur `web-01` (`192.168.100.65`) et sur `web-02` (`192.168.100.66`) en `root` :
   ```bash
   systemctl stop glusterd
   killall -9 glusterd glusterfs glusterfsd 2>/dev/null || true
   rm -rf /var/lib/glusterd/*
   rm -rf /data/glusterfs/web_brick/* /data/glusterfs/web_brick/.glusterfs
   setfattr -x trusted.glusterfs.volume-id /data/glusterfs/web_brick 2>/dev/null || true
   setfattr -x trusted.gfid /data/glusterfs/web_brick 2>/dev/null || true
   systemctl start glusterd
    ```
2. Établir l'appairage croisé :
    - Depuis web-01 :
    ```bash
    gluster peer probe 172.16.0.32
    ```
    - Depuis web-02 :
    ```bash
    gluster peer probe 172.16.0.31
    ```
3. Vérifier l'état du cluster :

- Sur les deux nœuds, lancer gluster peer status. La commande doit afficher Number of Peers: 1 et :
```
State: Peer in Cluster (Connected)
```

4. Rejouer l'automatisation Ansible :
- Depuis le conteneur bastion-01, relancer le playbook web :
```bash
cd ~/ansible-cluster
ansible-playbook -i hosts.ini web.yml
```
