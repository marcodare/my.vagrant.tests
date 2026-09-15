#!/usr/bin/env bash
set -euo pipefail
name=$1 address=$2 management_mac=$3 cluster_address=$4 cluster_mac=$5 hosts=$6
[[ $EUID == 0 && -d /home/vagrant ]] || exit 1
export DEBIAN_FRONTEND=noninteractive
hostnamectl set-hostname "$name"
sed -i '/# BEGIN K3S LAB/,/# END K3S LAB/d' /etc/hosts
# Le voci arrivano dal Vagrantfile, che le costruisce dai nodi di lab.json:
# così il file non elenca mai macchine assenti da questo laboratorio.
{
  echo '# BEGIN K3S LAB'
  tr ';' '\n' <<< "$hosts"
  echo '# END K3S LAB'
} >> /etc/hosts
cat > /etc/netplan/60-infra-lab.yaml <<EOF
network:
  version: 2
  ethernets:
    enpmgmt:
      match: {macaddress: "${management_mac,,}"}
      set-name: enpmgmt
      addresses: [$address/24]
    enpcluster:
      match: {macaddress: "${cluster_mac,,}"}
      set-name: enpcluster
      addresses: [$cluster_address/24]
      link-local: []
EOF
chmod 0600 /etc/netplan/60-infra-lab.yaml
netplan apply
apt-get update
apt-get install -y ca-certificates curl chrony
systemctl enable --now chrony
