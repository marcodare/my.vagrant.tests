#!/usr/bin/env bash
set -euo pipefail
role=$1 name=$2 address=$3 mac=$4 extras=$5 subnet=$6 hosts=$7
[[ $EUID == 0 && -d /home/vagrant ]] || { echo 'Solo guest Vagrant'; exit 1; }
[[ $address == "192.168.$subnet."* ]] || {
  echo "IP $address non appartiene alla rete 192.168.$subnet.0 del lab" >&2
  exit 1
}
export DEBIAN_FRONTEND=noninteractive
IFS=',' read -r external_mac _unused_ip _unused_bridge <<< "$extras"
hostnamectl set-hostname "$name"
sed -i '/# BEGIN INFRA LAB/,/# END INFRA LAB/d' /etc/hosts
sed -i -E "/^127\.[0-9.]+[[:space:]].*\b${name}\b/d" /etc/hosts
{
  echo '# BEGIN INFRA LAB'
  tr ';' '\n' <<< "$hosts"
  echo '# END INFRA LAB'
} >> /etc/hosts
apt-get update
apt-get install -y python3 python3-venv python3-dev git curl chrony build-essential libffi-dev libssl-dev libdbus-glib-1-dev
cat > /etc/netplan/60-infra-lab.yaml <<EOF
network:
  version: 2
  ethernets:
    enpmgmt:
      match: {macaddress: "$mac"}
      set-name: enpmgmt
      addresses: [$address/25]
      dhcp4: false
    enpext:
      match: {macaddress: "$external_mac"}
      set-name: enpext
      dhcp4: false
      dhcp6: false
      link-local: []
      optional: true
EOF
chmod 0600 /etc/netplan/60-infra-lab.yaml
netplan generate
netplan apply
systemctl enable --now chrony
mkdir -p /var/lib/infra-lab
echo "$role" > /var/lib/infra-lab/role
