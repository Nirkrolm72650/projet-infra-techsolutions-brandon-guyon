#!/usr/bin/env bash
set -euo pipefail

TF_DIR="$HOME/terraform-cluster"

echo "=================================================="
echo "    DESTRUCTION COMPLÈTE DE L'INFRASTRUCTURE     "
echo "=================================================="
echo "Attention : cette action va détruire les 6 machines virtuelles"
echo "sur Proxmox ainsi que toutes les données associées."
echo "=================================================="

read -rp "Confirmer la suppression totale ? (tapez 'oui') : " CONFIRM
if [[ "$CONFIRM" != "oui" ]]; then
  echo "[!] Annulation de la destruction."
  exit 0
fi

# 1. Destruction des ressources Terraform
echo -e "\n[*] 1/2 - Destruction des VMs Proxmox via Terraform..."
if [ -d "$TF_DIR" ]; then
  cd "$TF_DIR"
  terraform destroy -auto-approve
else
  echo "[!] Répertoire $TF_DIR introuvable !"
  exit 1
fi

# 2. Nettoyage des clés SSH sur le bastion
echo -e "\n[*] 2/2 - Nettoyage du fichier known_hosts sur le bastion..."
for ip in 192.168.100.{61..66}; do
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$ip" >/dev/null 2>&1 || true
done

echo -e "\n[✓] Cluster détruit et environnement prêt pour un nouveau déploiement."