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

if [[ ${1:-} == --check ]]; then
  VBoxManage --version
  vagrant --version
  test -c /dev/vboxdrv || { echo 'Driver VirtualBox non caricato: controllare DKMS/Secure Boot.'; exit 1; }
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
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/infra-oracle.gpg] https://download.virtualbox.org/virtualbox/debian $VERSION_CODENAME contrib" > /etc/apt/sources.list.d/infra-virtualbox.list
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/infra-hashicorp.gpg] https://apt.releases.hashicorp.com $VERSION_CODENAME main" > /etc/apt/sources.list.d/infra-vagrant.list
apt-get update
apt-get install -y virtualbox-7.2 vagrant git ruby python3 python3-venv shellcheck jq unzip nfs-common
usermod -aG vboxusers "$lab_user"

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
