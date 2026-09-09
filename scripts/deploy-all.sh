#!/usr/bin/env bash
set -e

TERRAFORM_DIR="$HOME/terraform-cluster"
ANSIBLE_DIR="$HOME/ansible-cluster"

# Liste des IPs d'administration à contrôler
VMS=(
  "192.168.100.61"
  "192.168.100.62"
  "192.168.100.63"
  "192.168.100.64"
  "192.168.100.65"
  "192.168.100.66"
)

echo "=========================================================="
echo "  1/3 - CRÉATION DE L'INFRASTRUCTURE (Terraform)"
echo "=========================================================="
cd "$TERRAFORM_DIR"
terraform init -upgrade
terraform apply -auto-approve

echo ""
echo "=========================================================="
echo "  2/3 - ATTENTE DE L'INITIALISATION SYSTÈME (Cloud-Init)"
echo "=========================================================="
for ip in "${VMS[@]}"; do
  echo -n "[*] Attente de la VM $ip... "
  until ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=2 debian@"$ip" "echo ok" >/dev/null >
    echo -n "."
    sleep 3
  done
  echo " Prête !"
done

echo ""
echo "=========================================================="
echo "  3/3 - CONFIGURATION DE LA PILE COMPLÈTE (Ansible)"
echo "=========================================================="
cd "$ANSIBLE_DIR"
ansible-playbook master.yml

echo ""
echo "=========================================================="
echo "  DÉPLOIEMENT TERMINÉ AVEC SUCCÈS !"
echo "=========================================================="