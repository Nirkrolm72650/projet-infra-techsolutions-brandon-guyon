#!/usr/bin/env python3
"""
TechSolutions Inc. - Automatisation Proxmox VE
Destruction sécurisée de machines virtuelles par plage de VMID.
"""

import sys
import time
import argparse
import urllib3
import requests

# Désactivation des avertissements SSL (certificat auto-signé Proxmox)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ==============================================================================
# CONFIGURATION DE L'ACCÈS API PROXMOX
# ==============================================================================
PVE_API_URL = "https://10.20.10.18:8006/api2/json"
PVE_TOKEN_ID = "terraform-prov@pve!terraform-token"
PVE_TOKEN_SECRET = "a2829a96-e1cf-4dd1-b379-3442877e7261"

HEADERS = {
    "Authorization": f"PVEAPIToken={PVE_TOKEN_ID}={PVE_TOKEN_SECRET}",
    "Accept": "application/json"
}

# ==============================================================================
# FONCTIONS API & UTILITAIRES
# ==============================================================================
def api_request(method, endpoint, params=None, data=None):
    """Envoie une requête à l'API Proxmox avec gestion d'erreurs HTTP."""
    url = f"{PVE_API_URL}{endpoint}"
    try:
        resp = requests.request(
            method=method,
            url=url,
            headers=HEADERS,
            params=params,
            data=data,
            verify=False,
            timeout=10
        )
        resp.raise_for_status()
        return resp.json().get("data", None)
    except requests.exceptions.HTTPError as err:
        code = err.response.status_code
        if code == 401:
            sys.exit("[ERREUR 401] Token API invalide ou expiré.")
        elif code == 403:
            sys.exit("[ERREUR 403] Droits insuffisants (PVEVMAdmin requis).")
        raise
    except requests.exceptions.ConnectionError:
        sys.exit(f"[ERREUR] Impossible de joindre l'API Proxmox sur {PVE_API_URL}.")
    except Exception as exc:
        raise RuntimeError(f"Erreur inattendue : {exc}") from exc


def wait_for_task(node, upid, timeout=60):
    """Suit l'avancement d'une tâche asynchrone Proxmox (arrêt/suppression)."""
    endpoint = f"/nodes/{node}/tasks/{upid}/status"
    start_time = time.time()
    while time.time() - start_time < timeout:
        task_data = api_request("GET", endpoint)
        if task_data and task_data.get("status") == "stopped":
            exitstatus = task_data.get("exitstatus")
            if exitstatus == "OK":
                return True
            print(f"    [!] Échec de la tâche Proxmox : {exitstatus}")
            return False
        time.sleep(2)
    print(f"    [!] Dépassement du délai d'attente ({timeout}s) pour la tâche.")
    return False


def get_all_vms():
    """Récupère l'inventaire complet des VMs du cluster Proxmox."""
    resources = api_request("GET", "/cluster/resources?type=vm")
    vms = {}
    for res in resources:
        if res.get("type") == "qemu":
            vms[res["vmid"]] = {
                "name": res.get("name", "sans-nom"),
                "node": res["node"],
                "status": res.get("status", "unknown")
            }
    return vms


def stop_vm(node, vmid):
    """Arrête une machine virtuelle si elle est en cours d'exécution."""
    print(f"  -> Envoi de l'ordre d'arrêt pour la VM {vmid}...")
    try:
        upid = api_request("POST", f"/nodes/{node}/qemu/{vmid}/status/stop")
        if upid and wait_for_task(node, upid, timeout=45):
            print(f"  [✓] VM {vmid} arrêtée.")
            return True
    except Exception as e:
        print(f"  [!] Avertissement lors de l'arrêt de la VM {vmid} : {e}")
    return False


def destroy_vm(node, vmid):
    """Supprime définitivement une VM et ses disques associés."""
    print(f"  -> Suppression de la VM {vmid} (purge des disques)...")
    try:
        # purge=1 supprime l'ensemble des disques et configurations résiduelles
        upid = api_request("DELETE", f"/nodes/{node}/qemu/{vmid}?purge=1&destroy-unreferenced-disks=1")
        if upid and wait_for_task(node, upid, timeout=60):
            print(f"  [✓] VM {vmid} ({node}) détruite avec succès.")
            return True
    except Exception as e:
        print(f"  [✗] Erreur lors de la destruction de la VM {vmid} : {e}")
    return False

# ==============================================================================
# POINT D'ENTRÉE PRINCIPAL
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="Suppression de VMs Proxmox par plage d'ID.")
    parser.add_argument("--start", type=int, help="VMID de début de plage")
    parser.add_argument("--end", type=int, help="VMID de fin de plage")
    parser.add_argument("--yes", action="store_true", help="Confirmer automatiquement la suppression")
    args = parser.parse_args()

    print("=" * 65)
    print("  OUTIL D'ADMINISTRATION : SUPPRESSION DE VMS PROXMOX")
    print("=" * 65)

    # Récupération interactive de la plage si non fournie en arguments
    start_id = args.start
    end_id = args.end

    while start_id is None:
        try:
            val = input("Entrez le VMID de début (ex: 100) : ").strip()
            start_id = int(val)
        except ValueError:
            print("Veuillez saisir un entier valide.")

    while end_id is None:
        try:
            val = input("Entrez le VMID de fin (ex: 130) : ").strip()
            end_id = int(val)
            if end_id < start_id:
                print("Le VMID de fin doit être supérieur ou égal au VMID de début.")
                end_id = None
        except ValueError:
            print("Veuillez saisir un entier valide.")

    print(f"\n[*] Scan du cluster pour les VMs entre {start_id} et {end_id}...")
    cluster_vms = get_all_vms()

    # Filtrer les VMs cibles
    targets = {vmid: info for vmid, info in cluster_vms.items() if start_id <= vmid <= end_id}

    if not targets:
        print(f"[!] Aucune VM trouvée dans la plage [{start_id} - {end_id}].")
        sys.exit(0)

    # Récapitulatif des machines identifiées
    print("\nVMs détectées à détruire :")
    print(f"  {'VMID':<8} {'NOM':<25} {'NŒUD':<15} {'STATUT':<10}")
    print("  " + "-" * 58)
    for vmid in sorted(targets.keys()):
        vm = targets[vmid]
        print(f"  {vmid:<8} {vm['name']:<25} {vm['node']:<15} {vm['status']:<10}")
    print("  " + "-" * 58)
    print(f"Total : {len(targets)} machine(s) virtuelle(s).\n")

    # Confirmation de sécurité
    if not args.yes:
        confirmation = input("Êtes-vous certain de vouloir DÉTRUIRE ces VMs ? (tapez 'oui') : ").strip().lower()
        if confirmation != "oui":
            print("[!] Opération annulée par l'utilisateur.")
            sys.exit(0)

    print("\n[*] Démarrage des destructions...")
    success_count = 0
    fail_count = 0

    for vmid in sorted(targets.keys()):
        vm_info = targets[vmid]
        node = vm_info["node"]
        print(f"\n[Traitement VM {vmid} : {vm_info['name']}]")

        # 1. Arrêt de la VM si elle est active
        if vm_info["status"] == "running":
            stop_vm(node, vmid)

        # 2. Suppression de la VM
        if destroy_vm(node, vmid):
            success_count += 1
        else:
            fail_count += 1

    print("\n" + "=" * 65)
    print(f"Bilan : {success_count} supprimée(s), {fail_count} échec(s).")
    print("=" * 65)


if __name__ == "__main__":
    main()