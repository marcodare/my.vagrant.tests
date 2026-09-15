#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
vagrant up --provider=virtualbox
