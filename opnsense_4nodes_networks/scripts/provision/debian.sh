#!/usr/bin/env bash
# Strumenti per osservare il traffico che attraversa il firewall. Nessun
# servizio in ascolto: i server di prova si avviano durante gli esercizi.
set -euo pipefail
[[ $EUID == 0 ]] || exit 1
export DEBIAN_FRONTEND=noninteractive
apt-get install -y iproute2 iputils-ping traceroute mtr-tiny tcpdump iperf3 \
  netcat-openbsd dnsutils nmap python3 vim tmux
