#!/usr/bin/env bash
# Strumenti comuni per gli esercizi di rete e confronto fra distribuzioni.
# Nessun servizio viene avviato: firewall e SELinux restano come da box.
set -euo pipefail
[[ $EUID == 0 ]] || exit 1
# shellcheck source=/dev/null
. /etc/os-release
case $ID in
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y iproute2 iputils-ping traceroute tcpdump iperf3 \
      netcat-openbsd dnsutils rsync vim tmux
    ;;
  rocky)
    dnf install -y iproute iputils traceroute tcpdump iperf3 nmap-ncat \
      bind-utils rsync vim-enhanced tmux
    ;;
  *)
    echo "Distribuzione non prevista dal lab: $ID" >&2
    exit 1
    ;;
esac
