#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
while IFS= read -r -d '' file; do bash -n "$file"; done < <(find . -name '*.sh' -not -path '*/.vagrant/*' -not -path '*/.venv/*' -print0)
while IFS= read -r -d '' file; do ruby -c "$file"; done < <(find . \( -name '*.rb' -o -name Vagrantfile \) -not -path '*/.vagrant/*' -not -path '*/.venv/*' -print0)
python3 scripts/check_layout.py
if command -v shellcheck >/dev/null; then
  find . -name '*.sh' -not -path '*/.vagrant/*' -not -path '*/.venv/*' -exec shellcheck {} +
else
  echo 'SKIP: shellcheck non installato.'
fi
if command -v vagrant >/dev/null; then
  for lab in */lab.json; do
    (cd "$(dirname "$lab")" && vagrant validate)
  done
else
  echo 'SKIP: vagrant non installato.'
fi
echo 'Controlli statici completati; nessuna VM avviata.'
