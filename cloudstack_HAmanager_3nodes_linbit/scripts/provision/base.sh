#!/usr/bin/env bash
# Due reti del lab: fake public su cloudbr1, privata/guest VLAN su cloudbr0.
set -euo pipefail
role=$1 name=$2 public_ip=$3 public_mac=$4 extras=$5 subnet=$6
export DEBIAN_FRONTEND=noninteractive
[[ $EUID == 0 && -d /home/vagrant ]] || { echo 'Solo guest Vagrant'; exit 1; }
[[ $subnet =~ ^(60|61|62)$ && $public_ip == "192.168.$subnet."* ]] || exit 1
[[ -n $extras && $extras != *';'* ]] || { echo 'Richiesta una rete privata'; exit 1; }
IFS=',' read -r private_mac private_ip _unused_bridge <<< "$extras"
hostnamectl set-hostname "$name"
sed -i '/# BEGIN INFRA LAB/,/# END INFRA LAB/d' /etc/hosts
sed -i -E "/^127\.[0-9.]+[[:space:]].*\b${name}\b/d" /etc/hosts
{
  echo '# BEGIN INFRA LAB'
  echo "10.$subnet.0.10 manager.lab.test manager"
  for n in 1 2 3; do
    echo "10.$subnet.0.$((10+n)) mgmt$n.lab.test mgmt$n"
    echo "10.$subnet.0.$((20+n)) kvm$n.lab.test kvm$n"
  done
  echo '# END INFRA LAB'
} >> /etc/hosts
apt-get update
apt-get install -y ca-certificates curl gnupg chrony sudo openssh-server
systemctl enable --now chrony
# Rinomina solo le NIC del lab tramite MAC; la NAT/SSH della box resta intatta.
cat > /etc/netplan/60-infra-lab.yaml <<EOF
network:
  version: 2
  ethernets:
    enplabpub:
      match: {macaddress: "$public_mac"}
      set-name: enplabpub
      dhcp4: false
      dhcp6: false
    enplabpriv:
      match: {macaddress: "$private_mac"}
      set-name: enplabpriv
      dhcp4: false
      dhcp6: false
  bridges:
    cloudbr1:
      interfaces: [enplabpub]
      addresses: [$public_ip/24]
      parameters: {stp: false, forward-delay: 0}
    cloudbr0:
      interfaces: [enplabpriv]
      addresses: [$private_ip/24]
      parameters: {stp: false, forward-delay: 0}
EOF
chmod 0600 /etc/netplan/60-infra-lab.yaml
netplan generate
netplan apply
install -d -m 0755 /var/lib/infra-lab
echo "$private_ip" > /var/lib/infra-lab/address
echo "$public_ip" > /var/lib/infra-lab/public-address
echo "$subnet" > /var/lib/infra-lab/subnet
echo "$role" > /var/lib/infra-lab/role
