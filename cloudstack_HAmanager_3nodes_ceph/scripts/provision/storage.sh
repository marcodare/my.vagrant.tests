#!/usr/bin/env bash
# Installa cephadm dal ramo Squid; bootstrap e creazione OSD sono manuali.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
[[ $(cat /var/lib/infra-lab/role) == kvm ]] || exit 1
apt-get install -y cephadm podman lvm2 python3
cephadm add-repo --release squid
cephadm install cephadm ceph-common
cephadm version
echo 'Pacchetti Ceph installati. Nessun OSD creato: seguire docs/storage.md.'
