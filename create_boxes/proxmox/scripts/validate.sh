#!/usr/bin/env bash
# Controlli statici del builder: non scarica ISO e non avvia VirtualBox.
set -euo pipefail

cd "$(dirname "$0")/.."

bash -n scripts/*.sh
# I placeholder devono restare letterali nei template versionati.
# shellcheck disable=SC2016
grep -q 'root-password-hashed = "${ROOT_PASSWORD_HASH}"' answer.toml.pkrtpl
grep -q 'disk-list = \["sda"\]' answer.toml.pkrtpl
grep -q 'guest_additions_mode.*=.*"disable"' proxmox.pkr.hcl
grep -q 'config.ssh.username.*vagrant' box/Vagrantfile

if command -v packer >/dev/null 2>&1; then
  packer fmt -check -recursive .
  packer validate -syntax-only .
else
  echo 'SALTATO: packer fmt/validate; Packer non installato.'
fi

echo 'Controlli statici del builder Proxmox completati; nessuna VM avviata.'
