#!/usr/bin/env bash
set -euo pipefail
# Backend, peer VRRP e priorità arrivano dal Vagrantfile, che li ricava da
# lab.json: lo script non deduce più nulla dall'hostname.
api_vip=$1 backends=$2 address=$3 peers=$4 priority=$5
[[ $EUID == 0 ]] || exit 1
[[ -n $api_vip && -n $backends && -n $address && -n $priority ]] || {
  echo 'Parametri del load balancer incompleti' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get install -y haproxy keepalived
cat > /etc/sysctl.d/90-haproxy.conf <<'EOF'
net.ipv4.ip_nonlocal_bind = 1
EOF
sysctl --system >/dev/null

# HAProxy ascolta su tutte le interfacce, non solo sul VIP: così l'API resta
# raggiungibile anche dalla NIC NAT, che VirtualBox usa per pubblicare la porta
# sull'host e quindi verso LAN/Tailscale. Con bind sul solo VIP il port forward
# arriverebbe su una porta chiusa. L'accesso resta autenticato da kubeconfig.
{
  cat <<'EOF'
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
  bind *:6443
  default_backend control-plane
backend control-plane
  option tcp-check
  balance roundrobin
EOF
  while IFS=',' read -r backend_name backend_ip; do
    [[ -n $backend_name ]] || continue
    echo "  server $backend_name $backend_ip:6443 check"
  done < <(tr ';' '\n' <<< "$backends")
} > /etc/haproxy/haproxy.cfg

# unicast_peer evita il multicast VRRP, che in VirtualBox è poco affidabile.
{
  echo 'vrrp_instance KUBE_API {'
  echo '  state BACKUP'
  echo '  interface enpmgmt'
  echo '  virtual_router_id 65'
  echo "  priority $priority"
  echo '  advert_int 1'
  echo "  unicast_src_ip $address"
  echo '  unicast_peer {'
  while IFS= read -r peer; do
    [[ -n $peer ]] || continue
    echo "    $peer"
  done < <(tr ';' '\n' <<< "$peers")
  echo '  }'
  echo "  virtual_ipaddress { $api_vip/24 dev enpmgmt }"
  echo '}'
} > /etc/keepalived/keepalived.conf
chmod 0600 /etc/keepalived/keepalived.conf

systemctl enable --now haproxy keepalived
systemctl reload haproxy || systemctl restart haproxy
