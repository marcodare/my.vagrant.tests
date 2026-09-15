#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || exit 1
modprobe br_netfilter
cat > /etc/sysctl.d/90-kubernetes.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system >/dev/null
