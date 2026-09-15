#!/usr/bin/env bash
set -euo pipefail
[[ $(cat /var/lib/infra-lab/role) == os-compute ]] || exit 1
modprobe kvm_amd
test -c /dev/kvm || { echo 'Nested KVM non disponibile'; exit 1; }
# Libvirt è installato nei container da Kolla: non installare libvirt sull'host.
echo 'Compute pronto per Kolla bootstrap-servers.'
