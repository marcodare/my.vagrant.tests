#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
vagrant up --provider=virtualbox
echo 'Nodi pronti: hostname, /etc/hosts, rete del lab e NTP configurati.'
echo 'Continuare con STEPS.md per verifiche ed esercizi.'
