#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
vagrant up --provider=virtualbox
echo 'Prerequisiti pronti. Continuare con STEPS.md per kubeadm e Cilium.'
echo 'A cluster installato: ./scripts/kubeconfig.sh per host e Mac.'
