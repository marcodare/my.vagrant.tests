#!/usr/bin/env bash
set -euo pipefail
name=$1 address=$2 management_mac=$3 cluster_address=$4 cluster_mac=$5
[[ $EUID == 0 && -d /home/vagrant ]] || exit 1
export DEBIAN_FRONTEND=noninteractive
hostnamectl set-hostname "$name"
sed -i '/# BEGIN K8S LAB/,/# END K8S LAB/d' /etc/hosts
cat >> /etc/hosts <<'EOF'
# BEGIN K8S LAB
192.168.65.5 kube-api.lab.test kube-api
10.65.0.2 lb1
10.65.0.3 lb2
10.65.0.11 control1
10.65.0.12 control2
10.65.0.13 control3
10.65.0.21 worker1
10.65.0.22 worker2
10.65.0.23 worker3
# END K8S LAB
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
apt-get install -y ca-certificates curl gpg chrony
systemctl enable --now chrony
