#!/usr/bin/env bash
# Estrae il kubeconfig del cluster e ne scrive due varianti:
#  - host:   passa dalla rete host-only, usabile solo dal Bosgame;
#  - remote: passa dalla porta pubblicata da VirtualBox, usabile dal Mac.
# Non avvia né modifica VM: richiede il cluster già installato con STEPS.md.
# Uso: ./scripts/kubeconfig.sh [indirizzo-remoto]
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

read -r host_address host_port < <(python3 -c '
import json
spec = json.load(open("lab.json"))
node = next(n for n in spec["nodes"] if n["name"] == "control1")
print("192.168.%d.%d" % (spec["subnet"], node["host"]), node["api_host_port"])
')

# Il percorso basic e quello assistito usano stati Vagrant distinti: si riusa la
# stessa variabile con cui il laboratorio è stato creato.
vagrant_env=${VAGRANT_VAGRANTFILE:-}
if [[ -n $vagrant_env ]]; then export VAGRANT_VAGRANTFILE=$vagrant_env; fi

raw=$(vagrant ssh "$node" -c 'sudo cat /etc/rancher/k3s/k3s.yaml' 2>/dev/null || true)
grep -q 'clusters:' <<< "$raw" || {
  echo "Kubeconfig non trovato su $node: installare prima K3s seguendo STEPS.md." >&2
  exit 1
}

# Si riscrive solo la riga server:, l'unica che dipende da dove si sta guardando.
write_variant() {
  local file=$1 endpoint=$2
  sed -E "s#^([[:space:]]*server:).*#\\1 https://${endpoint}#" <<< "$raw" > "$file"
  chmod 0600 "$file"
}

# L'estensione .local. è esclusa dal Git: il file contiene le credenziali admin.
write_variant kubeconfig.host.local.yaml "${host_address}:6443"
write_variant kubeconfig.remote.local.yaml "${remote_address}:${host_port}"

cat <<EOF
Scritti due kubeconfig (non versionati, contengono credenziali admin):

  kubeconfig.host.local.yaml     -> https://${host_address}:6443     dal Bosgame
  kubeconfig.remote.local.yaml   -> https://${remote_address}:${host_port}  dal Mac

Dal Bosgame:
  export KUBECONFIG=\$PWD/kubeconfig.host.local.yaml && kubectl get nodes

Sul Mac:
  scp $(whoami)@${remote_address}:$PWD/kubeconfig.remote.local.yaml ~/.kube/k3s-lab.yaml
  export KUBECONFIG=~/.kube/k3s-lab.yaml && kubectl get nodes

Se kubectl segnala un certificato non valido per ${remote_address}, K3s è stato
installato senza il --tls-san corrispondente: vedere STEPS.md.
EOF
