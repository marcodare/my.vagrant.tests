#!/usr/bin/env bash
# Trasforma il clone della box PVE in un nodo standalone con identità univoca.
set -euo pipefail

name=${1:?Hostname PVE mancante}
address=${2:?IP management mancante}
hosts=${3:?Elenco hosts mancante}
marker=/var/lib/infra-lab/pve-identity

[[ $EUID == 0 && -f /etc/infra-box-release ]] || {
  echo 'La finalizzazione richiede la box locale Proxmox.' >&2
  exit 1
}
# shellcheck source=/dev/null
source /etc/infra-box-release
[[ ${NAME:-} == local/proxmox-ve-9.2 \
  && ${PVE_TEMPLATE_HOSTNAME:-} == proxmox-template ]] || {
  echo 'Identità della box Proxmox inattesa.' >&2
  exit 1
}

# In VirtualBox un congelamento del guest oltre i 10 secondi può far scattare
# softdog durante il provisioning. Qui il watchdog resta diagnostico: registra
# l'evento senza resettare il nodo. Sul bare metal non applicare questa modifica.
softdog_conf=/etc/modprobe.d/infra-lab-softdog.conf
if [[ ! -f $softdog_conf ]]; then
  printf 'options softdog soft_noboot=1\n' > "$softdog_conf"
  systemctl stop pve-ha-lrm.service pve-ha-crm.service 2>/dev/null || true
  systemctl stop watchdog-mux.service
  modprobe -r softdog
  systemctl start watchdog-mux.service
  # Il messaggio può arrivare subito dopo il ritorno di systemctl. Attenderlo
  # senza grep -q: con pipefail la chiusura anticipata della pipe produrrebbe
  # un falso errore per il SIGPIPE di dmesg.
  timeout 10 bash -c \
    "until dmesg | grep 'softdog: initialized. soft_noboot=1' >/dev/null; do sleep 0.2; done" || {
    echo 'softdog non ricaricato con soft_noboot=1.' >&2
    exit 1
  }
fi

install -d -m 0755 "$(dirname "$marker")"
if [[ -f $marker ]]; then
  [[ $(<"$marker") == "$name" && $(hostname -s) == "$name" \
    && -d /etc/pve/nodes/"$name" ]] || {
    echo 'Nodo già finalizzato con una identità diversa o incompleta.' >&2
    exit 1
  }
  exit 0
fi

# Il ripristino dei loopback rende recuperabile anche un clone che sia stato
# interrotto mentre riscriveva /etc/hosts.
grep -qE '^127\.0\.0\.1[[:space:]]' /etc/hosts || {
  printf '127.0.0.1\tlocalhost\n::1\tlocalhost ip6-localhost ip6-loopback\n' >> /etc/hosts
}
sed -i '/# BEGIN INFRA LAB/,/# END INFRA LAB/d' /etc/hosts
sed -i -E "/^[^#].*[[:space:]](${name}|${PVE_TEMPLATE_HOSTNAME})(\.lab\.test)?([[:space:]]|$)/d" /etc/hosts
{
  echo '# BEGIN INFRA LAB'
  tr ';' '\n' <<< "$hosts"
  echo '# END INFRA LAB'
} >> /etc/hosts
grep -qE "^${address}[[:space:]]+${name}\.lab\.test[[:space:]]+${name}$" /etc/hosts
sync

if ! mountpoint -q /etc/pve; then
  systemctl reset-failed pve-cluster.service 2>/dev/null || true
  systemctl restart pve-cluster.service
  timeout 30 bash -c 'until mountpoint -q /etc/pve; do sleep 1; done'
fi
mountpoint -q /etc/pve || { echo 'pmxcfs non è montato.' >&2; exit 1; }

[[ ! -e /etc/pve/corosync.conf ]] || {
  echo 'Rifiuto il reset: il nodo appartiene già a un cluster.' >&2
  exit 1
}
if find /etc/pve/nodes -type f \
  \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) \
  -print -quit | grep -q .; then
  echo 'Rifiuto il reset: la box contiene già VM o container.' >&2
  exit 1
fi

systemctl stop pve-ha-lrm.service pve-ha-crm.service pvescheduler.service \
  pvestatd.service pveproxy.service pvedaemon.service 2>/dev/null || true
systemctl stop pve-cluster.service
mountpoint -q /etc/pve && {
  echo '/etc/pve ancora montato dopo lo stop.' >&2
  exit 1
}

# È sicuro eliminare il database solo sul clone standalone vuoto controllato
# sopra. Il successivo avvio genera CA, certificati e directory del nuovo nodo.
rm -f /var/lib/pve-cluster/config.db /var/lib/pve-cluster/config.db-*
rm -rf "/var/lib/rrdcached/db/pve2-node/$PVE_TEMPLATE_HOSTNAME" \
  "/var/lib/rrdcached/db/pve2-storage/$PVE_TEMPLATE_HOSTNAME"
hostnamectl set-hostname "$name"
systemctl start pve-cluster.service
timeout 30 bash -c 'until mountpoint -q /etc/pve; do sleep 1; done'
pvecm updatecerts --force
systemctl start pvedaemon.service pveproxy.service pvestatd.service \
  pvescheduler.service pve-ha-crm.service pve-ha-lrm.service

[[ -d /etc/pve/nodes/$name \
  && ! -e /etc/pve/nodes/$PVE_TEMPLATE_HOSTNAME ]] || {
  echo 'pmxcfs non ha assunto la nuova identità.' >&2
  exit 1
}
printf '%s\n' "$name" > "$marker"
