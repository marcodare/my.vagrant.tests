#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Errore alla riga $LINENO: configurazione interrotta." >&2' ERR

if [[ ${1:-} == --help ]]; then
  echo 'Uso: sudo ./configure.host.sh [--check]'
  echo 'Installa VirtualBox 7.2 e Vagrant dai repository ufficiali su Ubuntu 26.04 amd64.'
  echo '--check: controlli in sola lettura; eseguibile senza sudo.'
  exit 0
fi
[[ $# == 0 || ( $# == 1 && $1 == --check ) ]] || { echo 'Argomento non valido'; exit 2; }
[[ $(uname -s) == Linux ]] || { echo 'Richiesto host Linux Ubuntu 26.04.' >&2; exit 1; }
# shellcheck source=/dev/null
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 26.04 ]] || { echo 'Richiesto Ubuntu 26.04 LTS.' >&2; exit 1; }
[[ $(dpkg --print-architecture) == amd64 ]] || { echo 'Richiesta architettura amd64.' >&2; exit 1; }
grep -Eq '\b(svm|vmx)\b' /proc/cpuinfo || { echo 'Abilitare AMD SVM nel firmware.' >&2; exit 1; }

# VirtualBox su Linux autorizza le reti host-only solo se elencate qui. Senza il
# file vale il default 192.168.56.0/21, che si ferma a .63 e farebbe fallire
# `vagrant up` dei lab k3s/k8s su 192.168.64-65.
# Il file è condiviso con altri progetti: si aggiungono le righe mancanti e non
# si riscrive mai il contenuto esistente, per non revocare reti già in uso.
VBOX_NETWORKS_CONF=/etc/vbox/networks.conf
LAB_HOSTONLY_RANGES=('* 192.168.56.0/21' '* 192.168.64.0/21')

hostonly_ranges_missing() {
  local entry
  for entry in "${LAB_HOSTONLY_RANGES[@]}"; do
    # Un catch-all già presente copre qualsiasi range del progetto.
    grep -qE '^\*[[:space:]]+0\.0\.0\.0/0([[:space:]]|$)' "$VBOX_NETWORKS_CONF" 2>/dev/null && return 1
    grep -qF "$entry" "$VBOX_NETWORKS_CONF" 2>/dev/null || return 0
  done
  return 1
}

if [[ ${1:-} == --check ]]; then
  VBoxManage --version
  vagrant --version
  test -c /dev/vboxdrv || { echo 'Driver VirtualBox non caricato: controllare DKMS/Secure Boot.'; exit 1; }
  if hostonly_ranges_missing; then
    echo "Reti host-only del progetto non autorizzate in $VBOX_NETWORKS_CONF:" >&2
    printf '  %s\n' "${LAB_HOSTONLY_RANGES[@]}" >&2
    echo 'I lab k3s/k8s falliranno. Rieseguire sudo ./configure.host.sh.' >&2
    exit 1
  fi
  echo "Reti host-only del progetto autorizzate in $VBOX_NETWORKS_CONF."
  free -h
  df -h .
  command -v mokutil >/dev/null && mokutil --sb-state
  echo 'Controllo host superato; nested KVM va verificato anche dentro una VM.'
  exit 0
fi
[[ $EUID == 0 ]] || { echo 'Eseguire con sudo.' >&2; exit 1; }
lab_user=${SUDO_USER:-}
[[ -n $lab_user && $lab_user != root ]] || { echo 'Usare sudo dal proprio account, non una login root.' >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
# Un tentativo interrotto può aver lasciato sorgenti in conflitto con quelle già
# presenti sull'host, e in quel caso ogni apt-get update fallisce. Si rimuovono
# qui le sole sorgenti scritte da questo script, così il nuovo tentativo riparte
# pulito e add_repo può decidere di nuovo se servono davvero.
rm -f /etc/apt/sources.list.d/infra-virtualbox.list /etc/apt/sources.list.d/infra-vagrant.list
apt-get update
apt-get install -y ca-certificates curl gnupg dkms build-essential "linux-headers-$(uname -r)" mokutil
# Non usare repository di altre release come fallback.
curl -fsSLo /dev/null "https://download.virtualbox.org/virtualbox/debian/dists/$VERSION_CODENAME/Release"
curl -fsSLo /dev/null "https://apt.releases.hashicorp.com/dists/$VERSION_CODENAME/Release"
install -d -m 0755 /etc/apt/keyrings
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc -o "$tmp_dir/oracle.asc"
curl -fsSL https://apt.releases.hashicorp.com/gpg -o "$tmp_dir/hashicorp.asc"
gpg --batch --yes --dearmor -o /etc/apt/keyrings/infra-oracle.gpg "$tmp_dir/oracle.asc"
gpg --batch --yes --dearmor -o /etc/apt/keyrings/infra-hashicorp.gpg "$tmp_dir/hashicorp.asc"
chmod 0644 /etc/apt/keyrings/infra-{oracle,hashicorp}.gpg
# L'host può già avere lo stesso repository configurato da un'altra procedura,
# con il keyring in un percorso diverso. APT rifiuta due sorgenti per lo stesso
# repo con Signed-By discordanti e blocca ogni update successivo, quindi qui si
# rispetta la configurazione esistente invece di affiancarne una seconda.
add_repo() {
  local name=$1 url=$2 component=$3 keyring=$4
  local ours=/etc/apt/sources.list.d/infra-$name.list existing
  existing=$(grep -rlsF "$url" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null |
    grep -vxF "$ours" || true)
  if [[ -n $existing ]]; then
    rm -f "$ours"
    echo "Repository $name già configurato altrove, lasciato invariato:"
    while IFS= read -r found; do echo "  $found"; done <<< "$existing"
    return
  fi
  echo "deb [arch=amd64 signed-by=$keyring] $url $VERSION_CODENAME $component" > "$ours"
}

add_repo virtualbox https://download.virtualbox.org/virtualbox/debian contrib /etc/apt/keyrings/infra-oracle.gpg
add_repo vagrant https://apt.releases.hashicorp.com main /etc/apt/keyrings/infra-hashicorp.gpg
apt-get update
apt-get install -y virtualbox-7.2 vagrant git ruby python3 python3-venv shellcheck jq unzip nfs-common
usermod -aG vboxusers "$lab_user"

install -d -m 0755 /etc/vbox
if hostonly_ranges_missing; then
  # Solo append: eventuali range di altri laboratori restano validi.
  [[ -f $VBOX_NETWORKS_CONF ]] || printf '# Reti host-only consentite a VirtualBox.\n* ::/0\n' > "$VBOX_NETWORKS_CONF"
  for range in "${LAB_HOSTONLY_RANGES[@]}"; do
    grep -qF "$range" "$VBOX_NETWORKS_CONF" || echo "$range" >> "$VBOX_NETWORKS_CONF"
  done
  echo "Aggiunti i range host-only del progetto a $VBOX_NETWORKS_CONF."
fi
chmod 0644 "$VBOX_NETWORKS_CONF"

# Linux recente può occupare AMD-V già al caricamento di KVM.
# Non scaricare moduli o interrompere VM in esecuzione: applicare al prossimo boot.
echo 'options kvm enable_virt_at_load=0' > /etc/modprobe.d/infra-vagrant-kvm.conf
update-initramfs -u
if ! modprobe vboxdrv; then
  echo 'Driver non caricato: completare firma/MOK Secure Boot o controllare /var/log/vbox-setup.log.' >&2
  exit 1
fi
VBoxManage --version
vagrant --version
echo 'Installazione completata. Riavviare, poi eseguire ./configure.host.sh --check.'
echo 'Nessun Extension Pack necessario; nessuna modifica a firewall o reti fisiche.'
