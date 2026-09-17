#!/usr/bin/env bash
# Verifica il nodo PVE già installato nella box locale.
set -euo pipefail

series=${1:?Specificare la versione software da lab.json}
[[ $series == 9.2 ]] || {
  echo 'Versione non prevista da questo provisioner.' >&2
  exit 1
}
[[ -f /etc/infra-box-release && -f /var/lib/infra-lab/pve-identity ]] || {
  echo 'Nodo non inizializzato dalla box locale Proxmox.' >&2
  exit 1
}

# shellcheck source=/dev/null
source /etc/os-release
[[ $VERSION_CODENAME == trixie \
  && $(</var/lib/infra-lab/role) == pve ]] || exit 1

installed=$(dpkg-query -W -f='${Version}' pve-manager)
[[ $installed == "$series".* ]] || {
  echo "pve-manager $installed non appartiene al ramo $series." >&2
  exit 1
}
[[ $(uname -r) == *-pve ]] || {
  echo 'La box non usa il kernel PVE.' >&2
  exit 1
}
modprobe kvm_amd
[[ -c /dev/kvm ]] || {
  echo 'Nested KVM assente: verificare SVM e VirtualBox.' >&2
  exit 1
}
[[ ! -e /etc/pve/corosync.conf ]] || {
  echo 'Il mononodo deve restare standalone: cluster inatteso.' >&2
  exit 1
}

# Il reset dell'identità pmxcfs rimuove la registrazione degli storage creata
# nel template, non i relativi volumi. Li si registra nuovamente se presenti.
if ! pvesm status | awk 'NR>1 {print $1}' | grep -qx local; then
  pvesm add dir local --path /var/lib/vz --content iso,vztmpl,backup
fi
if lvs --noheadings -o lv_name pve 2>/dev/null \
  | awk '{$1=$1};1' | grep -qx data \
  && ! pvesm status | awk 'NR>1 {print $1}' | grep -qx local-lvm; then
  pvesm add lvmthin local-lvm --vgname pve --thinpool data \
    --content images,rootdir
fi

echo 'Nodo PVE standalone pronto. Impostare la password root e seguire README.md.'
