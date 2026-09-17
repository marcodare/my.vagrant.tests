#!/usr/bin/env bash
# Estrae il kubeconfig admin di kubeadm e ne scrive le varianti d'accesso:
#  - host:   VIP Keepalived sulla rete host-only, usabile solo dal Bosgame;
#  - remote: porta pubblicata da lb1 (e lb2 come riserva), usabile dal Mac.
# Non avvia né modifica VM: richiede il cluster già inizializzato con STEPS.md.
# Uso: ./scripts/kubeconfig.sh [indirizzo-remoto]
# Nel percorso basic mantenere VAGRANT_VAGRANTFILE=Vagrantfile.start: entrambe le
# definizioni condividono lo stato .vagrant, ma non vanno alternate.
set -euo pipefail
cd "$(dirname "$0")/.."

node=control1
remote_default=$(python3 -c '
import json
spec = json.load(open("lab.json"))
sans = [s for s in spec.get("api_sans", []) if s != "127.0.0.1"]
print(sans[0] if sans else "")
')
remote_address=${1:-$remote_default}
[[ -n $remote_address ]] || { echo 'Indicare un indirizzo remoto o popolare api_sans in lab.json' >&2; exit 1; }

# VIP dell'API e porte dei due load balancer, tutti da lab.json.
read -r vip primary_port secondary_port < <(python3 -c '
import json
spec = json.load(open("lab.json"))
lbs = [n for n in spec["nodes"] if n["role"] == "k8s-lb"]
print("192.168.%d.%d" % (spec["subnet"], spec["api_vip_host"]),
      lbs[0]["api_host_port"], lbs[1]["api_host_port"])
')

raw=$(vagrant ssh "$node" -c 'sudo cat /etc/kubernetes/admin.conf' 2>/dev/null || true)
grep -q 'clusters:' <<< "$raw" || {
  echo "Kubeconfig non trovato su $node: eseguire prima kubeadm init come da STEPS.md." >&2
  exit 1
}

write_variant() {
  local file=$1 endpoint=$2
  sed -E "s#^([[:space:]]*server:).*#\\1 https://${endpoint}#" <<< "$raw" > "$file"
  chmod 0600 "$file"
}

# L'estensione .local. è esclusa dal Git: i file contengono le credenziali admin.
write_variant kubeconfig.host.local.yaml "${vip}:6443"
write_variant kubeconfig.remote.local.yaml "${remote_address}:${primary_port}"
write_variant kubeconfig.remote-lb2.local.yaml "${remote_address}:${secondary_port}"

cat <<EOF
Scritti tre kubeconfig (non versionati, contengono credenziali admin):

  kubeconfig.host.local.yaml        -> https://${vip}:6443   VIP, dal Bosgame
  kubeconfig.remote.local.yaml      -> https://${remote_address}:${primary_port}   via lb1
  kubeconfig.remote-lb2.local.yaml  -> https://${remote_address}:${secondary_port}   via lb2

Dal Bosgame:
  export KUBECONFIG=\$PWD/kubeconfig.host.local.yaml && kubectl get nodes

Sul Mac:
  scp $(whoami)@${remote_address}:$PWD/kubeconfig.remote.local.yaml ~/.kube/k8s-lab.yaml
  export KUBECONFIG=~/.kube/k8s-lab.yaml && kubectl get nodes

Il VIP non è raggiungibile fuori dal Bosgame: da remoto si passa sempre da una
delle due porte pubblicate. Se lb1 è spento usare la variante lb2.
Certificato non valido per ${remote_address} significa kubeadm init senza il
--apiserver-cert-extra-sans corrispondente: vedere STEPS.md.
EOF
