#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
[[ $(cat /var/lib/infra-lab/role) == pbs ]] || exit 1
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg -o /usr/share/keyrings/proxmox-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pbs trixie pbs-no-subscription' > /etc/apt/sources.list.d/infra-pbs.list
for file in /etc/apt/sources.list.d/pbs-enterprise.list /etc/apt/sources.list.d/pbs-enterprise.sources; do
  if [[ -f $file ]]; then mv "$file" "$file.disabled"; fi
done
apt-get update
apt-get install -y proxmox-backup-server
for file in /etc/apt/sources.list.d/pbs-enterprise.list /etc/apt/sources.list.d/pbs-enterprise.sources; do
  if [[ -f $file ]]; then mv "$file" "$file.disabled"; fi
done
echo 'PBS installato. Configurare password e datastore seguendo il README; disco dati lasciato intatto.'
