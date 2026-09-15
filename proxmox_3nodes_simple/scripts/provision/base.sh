#!/usr/bin/env bash
set -euo pipefail
# hosts arriva dal Vagrantfile, costruito dai nodi dichiarati in lab.json.
role=$1 name=$2 address=$3 mac=$4 extras=$5 subnet=$6 hosts=$7
export DEBIAN_FRONTEND=noninteractive
[[ $EUID == 0 && -d /home/vagrant ]] || { echo 'Solo guest Vagrant'; exit 1; }
# Il controllo è legato alla subnet di questo laboratorio, non a un elenco fisso
# di subnet di altri lab: un IP incoerente va segnalato, non accettato in
# silenzio. Il messaggio evita un fallimento muto a metà provisioning.
[[ $address == "192.168.$subnet."* ]] || {
  echo "IP $address non appartiene alla rete 192.168.$subnet.0/24 del lab" >&2
  exit 1
}
# Questo laboratorio prevede solo nodi Proxmox: un ruolo diverso significa
# lab.json e provisioner disallineati.
[[ $role == pve || $role == pbs ]] || { echo "Ruolo $role non previsto" >&2; exit 1; }
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
    if [[ $(cat "$path/address") == "$1" ]]; then basename "$path"; return; fi
  done
  echo "NIC con MAC $1 assente" >&2
  return 1
}
nic=$(iface_for_mac "$mac")
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
install -d -m 0755 /var/lib/infra-lab
echo "$address" > /var/lib/infra-lab/address
echo "$role" > /var/lib/infra-lab/role
