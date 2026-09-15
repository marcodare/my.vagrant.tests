#!/usr/bin/env bash
set -euo pipefail
name=$1 address=$2 management_mac=$3 cluster_address=$4 cluster_mac=$5
[[ $EUID == 0 && -d /home/vagrant ]] || exit 1
export DEBIAN_FRONTEND=noninteractive
hostnamectl set-hostname "$name"
sed -i '/# BEGIN K3S LAB/,/# END K3S LAB/d' /etc/hosts
cat >> /etc/hosts <<'EOF'
# BEGIN K3S LAB
10.64.0.10 control1
10.64.0.21 worker1
10.64.0.22 worker2
10.64.0.23 worker3
# END K3S LAB
EOF
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
