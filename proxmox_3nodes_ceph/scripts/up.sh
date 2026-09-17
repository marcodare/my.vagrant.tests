#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
vagrant box list | grep -E '^local/proxmox-ve-9\.2[[:space:]]+\(virtualbox,[[:space:]]+0,' >/dev/null || {
  echo 'Box local/proxmox-ve-9.2 v0 assente: seguire ../create_boxes/proxmox/README.md.' >&2
  exit 1
}
vagrant up --provider=virtualbox
vagrant reload
