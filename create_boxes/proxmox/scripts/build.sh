#!/usr/bin/env bash
# Scarica, verifica e prepara l'ISO ufficiale, quindi costruisce la box con Packer.
set -euo pipefail

cd "$(dirname "$0")/.."

ISO_VERSION=9.2-1
ISO_NAME="proxmox-ve_${ISO_VERSION}.iso"
ISO_URL="https://enterprise.proxmox.com/iso/$ISO_NAME"
ISO_SHA256=4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c
RELEASE_KEY_URL=https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg
RELEASE_KEY_FINGERPRINT=24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E
PREVIOUS_RELEASE_KEY_URL=https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg
PREVIOUS_RELEASE_KEY_FINGERPRINT=F4E136C67CDCE41AE6DE6FC81140AF8F639E0C39
BOX_VERSION=9.2.1-1

mode=build
headless=true
force=false
for argument in "$@"; do
  case $argument in
    --check) mode=check ;;
    --prepare-only) mode=prepare ;;
    --gui) headless=false ;;
    --force) force=true ;;
    --help)
      cat <<'EOF'
Uso: ./scripts/build.sh [--check|--prepare-only] [--gui] [--force]

  --check         controlla i prerequisiti senza download o VM
  --prepare-only  scarica/verifica l'ISO e genera l'ISO unattended
  --gui           mostra la console VirtualBox durante la build
  --force         consente a Packer di sostituire output precedenti
EOF
      exit 0
      ;;
    *) echo "Argomento sconosciuto: $argument" >&2; exit 2 ;;
  esac
done

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Comando richiesto non trovato: $1" >&2
    return 1
  }
}

find_vagrant_public_key() {
  local candidate
  for candidate in \
    /opt/vagrant/embedded/gems/gems/vagrant-*/keys/vagrant.pub.ed25519 \
    /opt/vagrant/embedded/gems/gems/vagrant-*/keys/vagrant.pub; do
    [[ -f $candidate ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  echo 'Chiave pubblica insecure di Vagrant non trovata.' >&2
  return 1
}

require_command VBoxManage
require_command docker
require_command curl
require_command gpg
require_command gpgv
require_command openssl
require_command sha256sum
require_command envsubst
vagrant_public_key=$(find_vagrant_public_key)

if [[ $mode != prepare ]]; then
  require_command packer
fi

if [[ $mode == check ]]; then
  VBoxManage --version
  packer version
  docker --version
  docker info >/dev/null 2>&1 || {
    echo 'Docker non accessibile: verificare daemon e appartenenza al gruppo docker.' >&2
    exit 1
  }
  echo "Chiave pubblica Vagrant: $vagrant_public_key"
  echo 'Preparazione ISO: container tramite Docker.'
  echo 'Prerequisiti del builder presenti; nessuna VM o download avviato.'
  exit 0
fi

running_vms=$(VBoxManage list runningvms)
if [[ $mode == build && -n $running_vms ]]; then
  echo 'Sono presenti VM VirtualBox accese. Spegnerle prima della build.' >&2
  printf '%s\n' "$running_vms" >&2
  exit 1
fi

mkdir -p cache output
iso_path="$PWD/cache/$ISO_NAME"
signature_path="$iso_path.asc"
key_path="$PWD/cache/proxmox-release-trixie.gpg"
previous_key_path="$PWD/cache/proxmox-release-bookworm.gpg"
prepared_iso="$PWD/cache/proxmox-ve_${ISO_VERSION}.auto.iso"

curl --fail --location --continue-at - --output "$iso_path" "$ISO_URL"
curl --fail --location --output "$signature_path" "$ISO_URL.asc"
curl --fail --location --output "$key_path" "$RELEASE_KEY_URL"
curl --fail --location --output "$previous_key_path" "$PREVIOUS_RELEASE_KEY_URL"

printf '%s  %s\n' "$ISO_SHA256" "$iso_path" | sha256sum --check --status || {
  echo 'Checksum SHA-256 dell ISO non valido.' >&2
  exit 1
}
fingerprint=$(gpg --batch --with-colons --show-keys "$key_path" |
  awk -F: '$1 == "fpr" {print $10; exit}')
[[ $fingerprint == "$RELEASE_KEY_FINGERPRINT" ]] || {
  echo "Fingerprint inatteso per la chiave Proxmox: $fingerprint" >&2
  exit 1
}
previous_fingerprint=$(gpg --batch --with-colons --show-keys "$previous_key_path" |
  awk -F: '$1 == "fpr" {print $10; exit}')
[[ $previous_fingerprint == "$PREVIOUS_RELEASE_KEY_FINGERPRINT" ]] || {
  echo "Fingerprint inatteso per la chiave Proxmox precedente: $previous_fingerprint" >&2
  exit 1
}
gpgv --keyring "$key_path" --keyring "$previous_key_path" \
  "$signature_path" "$iso_path"

if [[ -z ${PROXMOX_BUILD_PASSWORD:-} ]]; then
  read -r -s -p 'Password root temporanea della VM builder: ' PROXMOX_BUILD_PASSWORD
  echo
  read -r -s -p 'Ripetere la password: ' password_confirmation
  echo
  [[ $PROXMOX_BUILD_PASSWORD == "$password_confirmation" ]] || {
    echo 'Le password non coincidono.' >&2
    exit 1
  }
fi
[[ ${#PROXMOX_BUILD_PASSWORD} -ge 12 ]] || {
  echo 'Usare una password temporanea di almeno 12 caratteri.' >&2
  exit 1
}

temp_dir=$(mktemp -d /tmp/proxmox-box-build.XXXXXX)
cleanup_temp() {
  unset PROXMOX_BUILD_PASSWORD PKR_VAR_ssh_password ROOT_PASSWORD_HASH
  rm -rf "$temp_dir"
}
trap cleanup_temp EXIT

ROOT_PASSWORD_HASH=$(printf '%s' "$PROXMOX_BUILD_PASSWORD" | openssl passwd -6 -stdin)
export ROOT_PASSWORD_HASH
# Il riferimento deve arrivare letterale a envsubst, che sostituisce soltanto
# questa variabile e non interpreta eventuali '$' contenuti nell'hash.
# shellcheck disable=SC2016
envsubst '${ROOT_PASSWORD_HASH}' < answer.toml.pkrtpl > "$temp_dir/answer.toml"

run_assistant() {
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    --volume "$PWD/cache:/cache:rw" \
    --volume "$temp_dir:/work:rw" \
    local/proxmox-auto-install-assistant:9.2 "$@"
}

docker build \
  --file containers/auto-assistant/Containerfile \
  --tag local/proxmox-auto-install-assistant:9.2 \
  containers/auto-assistant
assistant_iso=/cache/$ISO_NAME
assistant_answer=/work/answer.toml
assistant_output=/work/prepared.iso

run_assistant validate-answer "$assistant_answer" || exit 1
run_assistant prepare-iso "$assistant_iso" \
  --fetch-from iso \
  --answer-file "$assistant_answer" \
  --output "$assistant_output" || exit 1
mv "$temp_dir/prepared.iso" "$prepared_iso"
prepared_sha256=$(sha256sum "$prepared_iso" | awk '{print $1}')
echo "ISO unattended pronta: $prepared_iso"
echo "SHA-256: $prepared_sha256"

if [[ $mode == prepare ]]; then
  exit 0
fi

export PACKER_CACHE_DIR="$PWD/packer_cache"
export PKR_VAR_box_version=$BOX_VERSION
export PKR_VAR_headless=$headless
export PKR_VAR_prepared_iso_path=$prepared_iso
export PKR_VAR_prepared_iso_sha256=$prepared_sha256
export PKR_VAR_ssh_password=$PROXMOX_BUILD_PASSWORD
export PKR_VAR_vagrant_public_key_path=$vagrant_public_key

packer init .
packer validate .
packer_args=(build)
[[ $force == true ]] && packer_args+=(-force)
packer_args+=(.)
packer "${packer_args[@]}"

echo "Box pronta: output/proxmox-ve-${BOX_VERSION}-virtualbox-amd64.box"
echo 'La box non è ancora installata nel catalogo Vagrant locale.'
