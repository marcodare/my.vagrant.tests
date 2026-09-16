#!/usr/bin/env bash
# Debian 13: hostname, /etc/hosts, NIC di management, NIC del segmento interno
# e rotte verso gli altri segmenti via OPNsense. La default route resta sulla
# NIC NAT: spostarla sul firewall è uno degli esercizi di STEPS.md.
set -euo pipefail
name=$1 address=$2 mgmt_mac=$3 lab_address=$4 lab_mac=$5 gateway=$6 routes=$7 hosts=$8
[[ $EUID == 0 && -d /home/vagrant ]] || { echo 'Solo guest Vagrant'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
hostnamectl set-hostname "$name"
sed -i '/# BEGIN OPNSENSE LAB/,/# END OPNSENSE LAB/d' /etc/hosts
sed -i -E "/^127\.[0-9.]+[[:space:]].*\b${name}\b/d" /etc/hosts
# Le voci arrivano dal Vagrantfile, che le costruisce dai nodi di lab.json:
# così il file non elenca mai macchine assenti da questo laboratorio.
{
  echo '# BEGIN OPNSENSE LAB'
  tr ';' '\n' <<< "$hosts"
  echo '# END OPNSENSE LAB'
} >> /etc/hosts

iface_for_mac() {
  local path
  for path in /sys/class/net/*; do
    if [[ $(cat "$path/address") == "$1" ]]; then basename "$path"; return; fi
  done
  echo "NIC con MAC $1 assente" >&2
  return 1
}
mgmt_nic=$(iface_for_mac "$mgmt_mac")
lab_nic=$(iface_for_mac "$lab_mac")

# ifupdown è la rete della box Debian; il file resta separato da quello della
# NIC NAT così un errore qui non toglie l'accesso vagrant ssh.
mkdir -p /etc/network/interfaces.d
grep -q '^source /etc/network/interfaces.d/' /etc/network/interfaces ||
  echo 'source /etc/network/interfaces.d/*' >> /etc/network/interfaces
{
  cat <<CONF
auto $mgmt_nic
iface $mgmt_nic inet static
    address $address/24

auto $lab_nic
iface $lab_nic inet static
    address $lab_address/24
CONF
  IFS=',' read -ra targets <<< "$routes"
  for target in "${targets[@]}"; do
    echo "    up ip route replace $target via $gateway"
    echo "    down ip route del $target via $gateway || true"
  done
} > /etc/network/interfaces.d/60-infra-lab
ifdown --force "$mgmt_nic" "$lab_nic" >/dev/null 2>&1 || true
ifup "$mgmt_nic" "$lab_nic"

apt-get update
apt-get install -y ca-certificates curl chrony
systemctl enable --now chrony
install -d -m 0755 /var/lib/infra-lab
echo "$lab_address" > /var/lib/infra-lab/address
echo "$gateway" > /var/lib/infra-lab/gateway
