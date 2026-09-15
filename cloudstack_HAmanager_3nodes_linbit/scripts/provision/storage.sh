#!/usr/bin/env bash
# Pacchetti LINBIT community; non inizializza dischi né forma cluster.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
[[ $(cat /var/lib/infra-lab/role) == kvm ]] || exit 1
apt-get install -y software-properties-common "linux-headers-$(uname -r)" lvm2
add-apt-repository -y ppa:linbit/linbit-drbd9-stack
apt-get update
apt-get install -y drbd-dkms drbd-utils linstor-controller linstor-satellite linstor-client drbd-reactor resource-agents nfs-kernel-server
modprobe drbd
modinfo -F version drbd | grep -q '^9\.' || { echo 'Richiesto DRBD 9: riavviare dopo installazione DKMS'; exit 1; }
systemctl enable --now linstor-satellite
# Il controller verrà avviato prima su kvm1, poi gestito da DRBD Reactor.
if [[ ! -f /var/lib/infra-lab/storage-ready ]]; then
  systemctl disable --now linstor-controller nfs-server
fi
echo 'Pacchetti LINSTOR installati. Seguire docs/storage.md per pool, controller HA e NFS Gateway.'
