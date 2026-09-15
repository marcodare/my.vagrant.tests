#!/usr/bin/env bash
set -euo pipefail
series=${1:?Specificare la versione software da lab.json}
[[ $series == 9.2 ]] || { echo 'Versione non prevista da questo provisioner'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
# shellcheck source=/dev/null
source /etc/os-release
[[ $VERSION_CODENAME == trixie && $(cat /var/lib/infra-lab/role) == pve ]] || exit 1
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg -o /usr/share/keyrings/proxmox-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription' > /etc/apt/sources.list.d/infra-pve.list
# Disattiva solo il repository enterprise predefinito installato dal pacchetto.
for file in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.sources; do
  if [[ -f $file ]]; then mv "$file" "$file.disabled"; fi
done
cat > /etc/apt/preferences.d/infra-pve <<EOF
Package: proxmox-ve pve-manager
Pin: version $series.*
Pin-Priority: 1000

Package: proxmox-ve pve-manager
Pin: version *
Pin-Priority: -1
EOF
apt-get update
apt-get install -y proxmox-default-kernel
if [[ $(uname -r) != *-pve ]]; then
  echo 'Kernel installato. Eseguire vagrant reload, poi vagrant provision.'
  exit 0
fi
modprobe kvm_amd
[[ -c /dev/kvm ]] || { echo 'Nested KVM assente: verificare SVM/VirtualBox.' >&2; exit 1; }
echo 'postfix postfix/main_mailer_type select Local only' | debconf-set-selections
echo 'postfix postfix/mailname string lab.test' | debconf-set-selections
apt-get install -y "proxmox-ve=${series}.*" "pve-manager=${series}.*" postfix open-iscsi chrony
for file in /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.sources; do
  if [[ -f $file ]]; then mv "$file" "$file.disabled"; fi
done
# Un'installazione su Debian non crea il local-lvm dell'installer ISO.
if ! pvesm status | awk 'NR>1 {print $1}' | grep -qx local; then
  pvesm add dir local --path /var/lib/vz --content iso,vztmpl,backup,images,rootdir
fi
echo 'Proxmox installato. Impostare sudo passwd root via vagrant ssh; creare il cluster dal README.'
