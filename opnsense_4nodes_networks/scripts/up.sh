#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
vagrant up --provider=virtualbox
echo 'Debian configurati; OPNsense sta riavviando dopo il bootstrap (attendere circa un minuto).'
echo 'GUI: https://192.168.67.10 (root, password iniziale OPNsense da cambiare al primo accesso).'
echo 'Continuare con STEPS.md per regole, verifiche e fault test.'
