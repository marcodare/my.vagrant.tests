#!/usr/bin/env bash
set -euo pipefail
series=${1:?Specificare la versione software da lab.json}
[[ $series == 4.23 ]] || { echo 'Versione non prevista da questo provisioner'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
[[ $(cat /var/lib/infra-lab/role) == kvm ]] || exit 1
modprobe kvm_amd
[[ -c /dev/kvm ]] || { echo 'Nested KVM assente.' >&2; exit 1; }
curl -fsSL https://download.cloudstack.org/release.asc -o /usr/share/keyrings/infra-cloudstack.asc
echo "deb [signed-by=/usr/share/keyrings/infra-cloudstack.asc] https://download.cloudstack.org/ubuntu jammy $series" > /etc/apt/sources.list.d/infra-cloudstack.list
cat > /etc/apt/preferences.d/infra-cloudstack <<EOF
Package: cloudstack-*
Pin: version $series.*
Pin-Priority: 1000

Package: cloudstack-*
Pin: version *
Pin-Priority: -1
EOF
apt-get update
apt-get install -y "cloudstack-agent=${series}.*" qemu-kvm libvirt-daemon-system libvirt-clients nfs-common uuid-runtime
for key in listen_tls listen_tcp mdns_adv; do
  sed -i -E "/^[[:space:]]*${key}[[:space:]]*=/d" /etc/libvirt/libvirtd.conf
  echo "$key = 0" >> /etc/libvirt/libvirtd.conf
done
sed -i '/^[[:space:]]*LIBVIRTD_ARGS=/d' /etc/default/libvirtd
echo 'LIBVIRTD_ARGS="--listen"' >> /etc/default/libvirtd
if ! grep -Eq '^host_uuid[[:space:]]*=' /etc/libvirt/libvirtd.conf; then
  echo "host_uuid = \"$(uuidgen)\"" >> /etc/libvirt/libvirtd.conf
fi
systemctl mask libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket libvirtd-tls.socket libvirtd-tcp.socket
for profile in usr.sbin.libvirtd usr.lib.libvirt.virt-aa-helper; do
  if [[ -f /etc/apparmor.d/$profile ]]; then
    mkdir -p /etc/apparmor.d/disable
    ln -sf "/etc/apparmor.d/$profile" "/etc/apparmor.d/disable/$profile"
    if apparmor_status --enabled 2>/dev/null; then
      apparmor_parser -R "/etc/apparmor.d/$profile" 2>/dev/null || true
    fi
  fi
done
mkdir -p /var/lib/libvirt/images
for key in private.network.device public.network.device guest.network.device local.storage.path guest.cpu.mode; do
  sed -i "/^${key//./\.}=/d" /etc/cloudstack/agent/agent.properties
done
cat >> /etc/cloudstack/agent/agent.properties <<'EOF'
private.network.device=cloudbr0
public.network.device=cloudbr1
guest.network.device=cloudbr0
local.storage.path=/var/lib/libvirt/images
guest.cpu.mode=host-passthrough
EOF
systemctl enable libvirtd cloudstack-agent
systemctl restart libvirtd cloudstack-agent
echo 'KVM pronto. Preparare il disco locale e aggiungere questo host dalla UI usando utente vagrant.'
