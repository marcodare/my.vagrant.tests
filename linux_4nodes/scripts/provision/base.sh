#!/usr/bin/env bash
# Configura hostname, /etc/hosts, la NIC del lab e NTP su Ubuntu e Rocky.
set -euo pipefail
name=$1 address=$2 lab_mac=$3 hosts=$4
[[ $EUID == 0 && -d /home/vagrant ]] || { echo 'Solo guest Vagrant'; exit 1; }
hostnamectl set-hostname "$name"
sed -i '/# BEGIN LINUX LAB/,/# END LINUX LAB/d' /etc/hosts
# Le voci arrivano dal Vagrantfile, che le costruisce dai nodi di lab.json:
# così il file non elenca mai macchine assenti da questo laboratorio.
{
  echo '# BEGIN LINUX LAB'
  tr ';' '\n' <<< "$hosts"
  echo '# END LINUX LAB'
} >> /etc/hosts

# La NIC è identificata dal MAC, non dal nome: le due famiglie di distribuzioni
# nominano le interfacce in modo diverso e la NIC NAT deve restare la default.
# shellcheck source=/dev/null
. /etc/os-release
case $ID in
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    cat > /etc/netplan/60-infra-lab.yaml <<YAML
network:
  version: 2
  ethernets:
    enplab:
      match: {macaddress: "$lab_mac"}
      set-name: enplab
      addresses: [$address/24]
      dhcp4: false
YAML
    chmod 0600 /etc/netplan/60-infra-lab.yaml
    netplan generate
    netplan apply
    apt-get update
    apt-get install -y ca-certificates curl chrony
    systemctl enable --now chrony
    ;;
  rocky)
    nmcli connection delete lab >/dev/null 2>&1 || true
    nmcli connection add type ethernet con-name lab \
      802-3-ethernet.mac-address "$lab_mac" \
      ipv4.method manual ipv4.addresses "$address/24" ipv4.never-default yes \
      ipv6.method disabled connection.autoconnect yes
    nmcli connection up lab
    dnf install -y ca-certificates curl chrony
    systemctl enable --now chronyd
    ;;
  *)
    echo "Distribuzione non prevista dal lab: $ID" >&2
    exit 1
    ;;
esac
