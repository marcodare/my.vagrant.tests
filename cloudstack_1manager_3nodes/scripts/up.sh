#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
VAGRANT_VAGRANTFILE=Vagrantfile vagrant up --provider=virtualbox
