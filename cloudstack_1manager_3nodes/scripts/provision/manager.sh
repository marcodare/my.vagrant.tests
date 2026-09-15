#!/usr/bin/env bash
set -euo pipefail
series=${1:?Specificare la versione software da lab.json}
[[ $series == 4.23 ]] || { echo 'Versione non prevista da questo provisioner'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
[[ $(cat /var/lib/infra-lab/role) == manager ]] || exit 1
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
apt-get install -y "cloudstack-management=${series}.*" mysql-server nfs-kernel-server iptables-persistent dnsmasq
cat > /etc/mysql/mysql.conf.d/infra-cloudstack.cnf <<'EOF'
[mysqld]
server-id=1
innodb_rollback_on_timeout=1
innodb_lock_wait_timeout=600
max_connections=350
log-bin=mysql-bin
binlog-format=ROW
bind-address=127.0.0.1
EOF
systemctl restart mysql
address=$(cat /var/lib/infra-lab/address)
# Marker solo dopo successo. Non re-inizializzare un database già esistente.
if [[ ! -f /var/lib/infra-lab/cloudstack-db-ready ]]; then
  if mysql -Nse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='cloud'" | grep -qx cloud; then
    echo 'Database cloud già presente: verificare lo stato prima di riprendere setup.' >&2
    exit 1
  fi
  db_password=$(openssl rand -hex 24)
  deploy_password=$(openssl rand -hex 24)
  management_key=$(openssl rand -hex 24)
  database_key=$(openssl rand -hex 24)
  mysql <<SQL
CREATE USER IF NOT EXISTS 'infra_deploy'@'localhost' IDENTIFIED WITH mysql_native_password BY '$deploy_password';
ALTER USER 'infra_deploy'@'localhost' IDENTIFIED WITH mysql_native_password BY '$deploy_password';
GRANT ALL PRIVILEGES ON *.* TO 'infra_deploy'@'localhost' WITH GRANT OPTION;
SQL
  trap 'mysql -e "DROP USER IF EXISTS '\''infra_deploy'\''@'\''localhost'\''"' EXIT
  # Il tool upstream riceve segreti negli argomenti: solo dentro il guest di studio.
  install -m 0600 /dev/null /var/log/infra-cloudstack-db.log
  cloudstack-setup-databases "cloud:$db_password@localhost" \
    "--deploy-as=infra_deploy:$deploy_password" -e file -m "$management_key" -k "$database_key" -i "$address" \
    > /var/log/infra-cloudstack-db.log 2>&1
  chmod 0600 /var/log/infra-cloudstack-db.log
  mysql -e "DROP USER IF EXISTS 'infra_deploy'@'localhost'"
  trap - EXIT
  touch /var/lib/infra-lab/cloudstack-db-ready
fi
cloudstack-setup-management
mkdir -p /srv/secondary
echo '/srv/secondary 10.60.0.0/24(rw,async,no_root_squash,no_subtree_check)' > /etc/exports.d/infra-cloudstack.exports
exportfs -ra
systemctl enable --now nfs-kernel-server

# Il manager è il router del solo segmento virtuale del lab, non dell'host.
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/90-infra-router.conf
sysctl --system >/dev/null
nat=$(ip -4 route show default | awk 'NR==1 {print $5}')
[[ -n $nat && $nat != cloudbr0 ]] || exit 1
iptables -t nat -C POSTROUTING -s 192.168.60.0/24 -o "$nat" -j MASQUERADE 2>/dev/null ||
  iptables -t nat -A POSTROUTING -s 192.168.60.0/24 -o "$nat" -j MASQUERADE
iptables -C FORWARD -i cloudbr1 -o "$nat" -j ACCEPT 2>/dev/null ||
  iptables -A FORWARD -i cloudbr1 -o "$nat" -j ACCEPT
iptables -C FORWARD -i "$nat" -o cloudbr1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null ||
  iptables -A FORWARD -i "$nat" -o cloudbr1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.60.0.0/24 -o "$nat" -j MASQUERADE 2>/dev/null ||
  iptables -t nat -A POSTROUTING -s 10.60.0.0/24 -o "$nat" -j MASQUERADE
iptables -C FORWARD -i cloudbr0 -o "$nat" -j ACCEPT 2>/dev/null ||
  iptables -A FORWARD -i cloudbr0 -o "$nat" -j ACCEPT
iptables -C FORWARD -i "$nat" -o cloudbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null ||
  iptables -A FORWARD -i "$nat" -o cloudbr0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
netfilter-persistent save
cat > /etc/dnsmasq.d/infra-lab.conf <<'EOF'
interface=cloudbr0
interface=cloudbr1
bind-dynamic
listen-address=192.168.60.10,10.60.0.10
no-resolv
server=1.1.1.1
server=8.8.8.8
EOF
systemctl restart dnsmasq
echo 'Manager pronto. Importare il template System VM e creare la zona dal README.'
