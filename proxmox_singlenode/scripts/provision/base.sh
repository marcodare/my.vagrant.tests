#!/usr/bin/env bash
set -euo pipefail

# Gli argomenti sono costruiti esclusivamente dal Vagrantfile locale.
role=$1 name=$2 address=$3 mac=$4 extras=$5 subnet=$6 hosts=$7
export DEBIAN_FRONTEND=noninteractive

[[ $EUID == 0 && -d /home/vagrant ]] || {
  echo 'Questo provisioner può essere eseguito solo nel guest Vagrant.' >&2
  exit 1
}
[[ $role == pve ]] || { echo "Ruolo $role non previsto." >&2; exit 1; }
[[ $address == "192.168.$subnet."* ]] || {
  echo "IP $address non appartiene alla rete 192.168.$subnet.0/24 del lab." >&2
  exit 1
}

hostnamectl set-hostname "$name"
sed -i '/# BEGIN INFRA LAB/,/# END INFRA LAB/d' /etc/hosts
sed -i -E "/^127\.[0-9.]+[[:space:]].*\b${name}\b/d" /etc/hosts
{
  echo '# BEGIN INFRA LAB'
  tr ';' '\n' <<< "$hosts"
  echo '# END INFRA LAB'
} >> /etc/hosts

apt-get update
apt-get install -y ca-certificates curl gnupg chrony sudo openssh-server
systemctl enable --now chrony

iface_for_mac() {
  local path
  for path in /sys/class/net/*; do
    [[ -f $path/address ]] || continue
    if [[ $(<"$path/address") == "$1" ]]; then
      basename "$path"
      return
    fi
  done
  echo "NIC con MAC $1 assente." >&2
  return 1
}

management_nic=$(iface_for_mac "$mac")
apt-get install -y ifupdown2 isc-dhcp-client

# La box creata dall'ISO usa inizialmente vmbr0 per la NIC NAT. Si individua
# la porta fisica del bridge prima di riassegnare vmbr0 alla NIC management.
nat_nic=$(ip -4 route show default | awk 'NR==1 {print $5}')
if [[ -n $nat_nic && -d /sys/class/net/$nat_nic/brif ]]; then
  nat_nic=$(find /sys/class/net/"$nat_nic"/brif -mindepth 1 -maxdepth 1 -printf '%f\n' | head -n 1)
fi
[[ -n $nat_nic && $nat_nic != "$management_nic" && $nat_nic != vmbr* \
  && -d /sys/class/net/$nat_nic/device ]] || {
  echo "NIC NAT non identificata (default route: $(ip -4 route show default | head -n 1))." >&2
  exit 1
}

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $nat_nic
iface $nat_nic inet dhcp

iface $management_nic inet manual

auto vmbr0
iface vmbr0 inet static
    address $address/24
    bridge-ports $management_nic
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
EOF

# Il lab non dichiara reti aggiuntive; il supporto rimane locale per eventuali
# estensioni esplicite di lab.json e del Vagrantfile.
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
install -d -m 0755 /var/lib/infra-lab
printf '%s\n' "$address" > /var/lib/infra-lab/address
printf '%s\n' "$role" > /var/lib/infra-lab/role
