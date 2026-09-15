#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ZS_VAGRANT_PASSWORD:?Impostare la password vagrant della box locale (README)}"
vagrant box list | grep -q '^local/zsvirt-h84r ' || { echo 'Preparare prima la box da OVA ufficiale: leggere README.md'; exit 1; }
vagrant up --provider=virtualbox
