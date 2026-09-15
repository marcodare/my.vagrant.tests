#!/usr/bin/env bash
set -euo pipefail
role=$1 name=$2 address=$3 mac=$4 extras=$5 subnet=$6
export DEBIAN_FRONTEND=noninteractive
[[ $EUID == 0 && -d /home/vagrant ]] || { echo 'Solo guest Vagrant'; exit 1; }
[[ $address =~ ^192\.168\.(56|57|58|59|60)\.[0-9]+$ ]] || exit 1
hostnamectl set-hostname "$name"
sed -i '/# BEGIN INFRA LAB/,/# END INFRA LAB/d' /etc/hosts
sed -i -E "/^127\.[0-9.]+[[:space:]].*\b${name}\b/d" /etc/hosts
{
  echo '# BEGIN INFRA LAB'
  for n in 1 2 3; do echo "192.168.$subnet.$((10+n)) pve$n.lab.test pve$n"; done
  echo "192.168.$subnet.20 pbs1.lab.test pbs1"
  echo "192.168.$subnet.10 manager.lab.test manager"
  for n in 1 2 3; do echo "192.168.$subnet.$((20+n)) kvm$n.lab.test kvm$n"; done
  echo '# END INFRA LAB'
} >> /etc/hosts
apt-get update
apt-get install -y ca-certificates curl gnupg chrony sudo openssh-server
systemctl enable --now chrony

iface_for_mac() {
  local path
  for path in /sys/class/net/*; do
    if [[ $(cat "$path/address") == "$1" ]]; then basename "$path"; return; fi
  done
  echo "NIC con MAC $1 assente" >&2
  return 1
}
nic=$(iface_for_mac "$mac")
if [[ $role == pve || $role == pbs ]]; then
  apt-get install -y ifupdown2
  nat=$(ip -4 route show default | awk 'NR==1 {print $5}')
  [[ -n $nat && $nat != "$nic" && $nat != vmbr* ]] || { echo 'NIC NAT non identificata'; exit 1; }
  # Il primo boot conserva la rete corrente; il nuovo layout entra al reload.
  cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
auto $nat
iface $nat inet dhcp
iface $nic inet manual
auto vmbr0
iface vmbr0 inet static
    address $address/24
    bridge-ports $nic
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
EOF
  if [[ -n $extras ]]; then
    IFS=';' read -ra networks <<< "$extras"
    for network in "${networks[@]}"; do
      IFS=',' read -r extra_mac extra_ip bridge <<< "$network"
      extra_nic=$(iface_for_mac "$extra_mac")
      cat >> /etc/network/interfaces <<EOF
iface $extra_nic inet manual
auto $bridge
iface $bridge inet static
    address $extra_ip/24
    bridge-ports $extra_nic
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
EOF
    done
  fi
  systemctl disable systemd-networkd.service systemd-networkd.socket 2>/dev/null || true
  systemctl enable networking
else
  # Gestione, guest e traffico NFS sul medesimo segmento del lab CloudStack.
  cat > /etc/netplan/60-infra-lab.yaml <<EOF
network:
  version: 2
  ethernets:
    $nic:
      match:
        macaddress: "$mac"
      dhcp4: false
      dhcp6: false
  bridges:
    cloudbr0:
      interfaces: [$nic]
      addresses: [$address/24]
      parameters:
        stp: false
        forward-delay: 0
EOF
  chmod 0600 /etc/netplan/60-infra-lab.yaml
  netplan generate
  netplan apply
fi
install -d -m 0755 /var/lib/infra-lab
echo "$address" > /var/lib/infra-lab/address
echo "$role" > /var/lib/infra-lab/role
