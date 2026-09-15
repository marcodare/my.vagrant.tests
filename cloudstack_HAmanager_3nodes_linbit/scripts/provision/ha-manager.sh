#!/usr/bin/env bash
# Prepara i tre control node; DB cluster e schema CloudStack sono esercizi guidati.
set -euo pipefail
series=${1:?Specificare la versione software da lab.json}
[[ $series == 4.23 ]] || { echo 'Versione non prevista da questo provisioner'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
[[ $(cat /var/lib/infra-lab/role) == ha-manager ]] || exit 1
subnet=$(cat /var/lib/infra-lab/subnet)
address=$(cat /var/lib/infra-lab/address)
node_number=${address##*.}
curl -fsSL https://download.cloudstack.org/release.asc -o /usr/share/keyrings/infra-cloudstack.asc
echo "deb [signed-by=/usr/share/keyrings/infra-cloudstack.asc] https://download.cloudstack.org/ubuntu jammy $series" > /etc/apt/sources.list.d/infra-cloudstack.list
cat > /etc/apt/preferences.d/infra-cloudstack <<EOF
Package: cloudstack-*
Pin: version $series.*
Pin-Priority: 1000

Package: cloudstack-*
Pin: version *
Pin-Priority: -1
EOF
apt-get update
apt-get install -y "cloudstack-management=${series}.*" mysql-server mysql-router haproxy keepalived dnsmasq iptables-persistent nfs-common
# Senza schema e segreti comuni il manager non deve avviarsi come cluster separato.
if [[ ! -f /var/lib/infra-lab/management-ready ]]; then
  systemctl disable --now cloudstack-management
fi
cat > /etc/mysql/mysql.conf.d/infra-cloudstack.cnf <<EOF
[mysqld]
server-id=$node_number
bind-address=127.0.0.1,$address
report_host=$address
innodb_rollback_on_timeout=1
innodb_lock_wait_timeout=600
max_connections=1050
log-bin=mysql-bin
binlog-format=ROW
gtid_mode=ON
enforce_gtid_consistency=ON
log_replica_updates=ON
EOF
systemctl restart mysql
# La UI ascolta sulla VIP:80; i manager mantengono la loro porta 8080.
# Gli agent collegano direttamente tutti i manager; non usare un LB TCP unico.
cat > /etc/haproxy/haproxy.cfg <<EOF
global
  log /dev/log local0
  user haproxy
  group haproxy
  daemon
defaults
  log global
  mode http
  timeout connect 5s
  timeout client 1h
  timeout server 1h
frontend cloudstack
  bind 192.168.$subnet.5:80
  bind 10.$subnet.0.5:80
  default_backend managers
backend managers
  balance roundrobin
  cookie NODE insert indirect nocache
  option httpchk GET /client/
  http-check expect rstatus (2|3)[0-9][0-9]
  server mgmt1 10.$subnet.0.11:8080 check cookie m1
  server mgmt2 10.$subnet.0.12:8080 check cookie m2
  server mgmt3 10.$subnet.0.13:8080 check cookie m3
EOF
cat > /etc/sysctl.d/90-infra-ha.conf <<'EOF'
net.ipv4.ip_nonlocal_bind=1
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null
# VRRP unicast tra manager; le VIP includono gateway e API dei due segmenti.
cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
  router_id mgmt$node_number
  enable_script_security
  script_user root
}
vrrp_script haproxy_alive {
  script "/usr/bin/pgrep -x haproxy"
  interval 2
  fall 2
  rise 2
}
vrrp_instance LAB {
  state BACKUP
  interface cloudbr0
  virtual_router_id $subnet
  priority $((150-node_number))
  advert_int 1
  unicast_src_ip $address
  unicast_peer {
EOF
for n in 11 12 13; do
  [[ $n == "$node_number" ]] || echo "    10.$subnet.0.$n" >> /etc/keepalived/keepalived.conf
done
cat >> /etc/keepalived/keepalived.conf <<EOF
  }
  virtual_ipaddress {
    10.$subnet.0.4/24 dev cloudbr0
    10.$subnet.0.5/24 dev cloudbr0
    192.168.$subnet.4/24 dev cloudbr1
    192.168.$subnet.5/24 dev cloudbr1
  }
  track_script {
    haproxy_alive
  }
}
EOF
cat > /etc/dnsmasq.d/infra-lab.conf <<EOF
interface=cloudbr0
interface=cloudbr1
bind-dynamic
listen-address=10.$subnet.0.4,192.168.$subnet.4
no-resolv
server=1.1.1.1
server=8.8.8.8
EOF
nat=$(ip -4 route show default | awk 'NR==1 {print $5}')
[[ -n $nat && $nat != cloudbr* ]] || exit 1
for cidr in "192.168.$subnet.0/24" "10.$subnet.0.0/24"; do
  iptables -t nat -C POSTROUTING -s "$cidr" -o "$nat" -j MASQUERADE 2>/dev/null ||
    iptables -t nat -A POSTROUTING -s "$cidr" -o "$nat" -j MASQUERADE
done
for bridge in cloudbr0 cloudbr1; do
  iptables -C FORWARD -i "$bridge" -o "$nat" -j ACCEPT 2>/dev/null || iptables -A FORWARD -i "$bridge" -o "$nat" -j ACCEPT
  iptables -C FORWARD -i "$nat" -o "$bridge" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null ||
    iptables -A FORWARD -i "$nat" -o "$bridge" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
done
netfilter-persistent save
haproxy -c -f /etc/haproxy/haproxy.cfg
keepalived --config-test
systemctl enable haproxy keepalived dnsmasq
systemctl restart haproxy keepalived dnsmasq
echo 'Base HA pronta: completare DB, manager e storage dal runbook; UI può restituire 503 finché i backend sono fermi.'
