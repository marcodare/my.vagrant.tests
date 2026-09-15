#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
vagrant up
echo 'Prerequisiti pronti. Continuare con STEPS.md per kubeadm e Cilium.'
