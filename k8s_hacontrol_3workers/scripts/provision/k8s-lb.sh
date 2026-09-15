#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || exit 1
export DEBIAN_FRONTEND=noninteractive
apt-get install -y haproxy keepalived
cat > /etc/sysctl.d/90-haproxy.conf <<'EOF'
net.ipv4.ip_nonlocal_bind = 1
EOF
sysctl --system >/dev/null
cat > /etc/haproxy/haproxy.cfg <<'EOF'
global
  log /dev/log local0
  user haproxy
  group haproxy
defaults
  log global
  mode tcp
  timeout connect 5s
  timeout client 50s
  timeout server 50s
frontend kubernetes-api
  bind 192.168.65.5:6443
  default_backend control-plane
backend control-plane
  option tcp-check
  balance roundrobin
  server control1 10.65.0.11:6443 check
  server control2 10.65.0.12:6443 check
  server control3 10.65.0.13:6443 check
EOF
priority=100
peer=192.168.65.3
[[ $(hostname) == lb2 ]] && { priority=90; peer=192.168.65.2; }
cat > /etc/keepalived/keepalived.conf <<EOF
vrrp_instance KUBE_API {
  state BACKUP
  interface enpmgmt
  virtual_router_id 65
  priority $priority
  advert_int 1
  unicast_src_ip 192.168.65.$([[ $(hostname) == lb1 ]] && echo 2 || echo 3)
  unicast_peer { $peer }
  virtual_ipaddress { 192.168.65.5/24 dev enpmgmt }
}
EOF
systemctl enable --now haproxy keepalived
