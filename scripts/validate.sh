#!/usr/bin/env bash
# Controlli statici: non avvia VM e non modifica l'host.
# Ogni strumento assente viene saltato e riepilogato, senza interrompere il resto.
set -euo pipefail
cd "$(dirname "$0")/.."

skipped=()

while IFS= read -r -d '' file; do bash -n "$file"; done < <(find . -name '*.sh' -not -path '*/.vagrant/*' -not -path '*/.venv/*' -print0)
echo 'OK: sintassi Bash.'

# Ruby serve solo a controllare la DSL Vagrant. Sulla macchina di sviluppo può
# mancare: senza questo guard l'intero script si fermava qui per via di set -e,
# saltando silenziosamente tutti i controlli successivi.
if command -v ruby >/dev/null; then
  while IFS= read -r -d '' file; do ruby -c "$file" >/dev/null; done < <(find . \( -name '*.rb' -o -name Vagrantfile -o -name Vagrant.start -o -name Vagrantfile.start \) -not -path '*/.vagrant/*' -not -path '*/.venv/*' -print0)
  echo 'OK: sintassi Ruby dei Vagrantfile.'
else
  skipped+=('ruby: sintassi Vagrantfile non verificata')
fi

python3 scripts/check_layout.py

# I builder non fanno parte dei lab e non vengono eseguiti automaticamente.
# Il loro validatore controlla soltanto template e sintassi, senza download o VM.
if [[ -x create_boxes/proxmox/scripts/validate.sh ]]; then
  create_boxes/proxmox/scripts/validate.sh
fi

# Il pacchetto shellcheck-py è nel dependency group dev, quindi sotto `uv run`
# il binario è nel PATH del venv anche senza il pacchetto di sistema.
if command -v shellcheck >/dev/null; then
  find . -name '*.sh' -not -path '*/.vagrant/*' -not -path '*/.venv/*' -exec shellcheck {} +
  echo 'OK: shellcheck.'
else
  skipped+=('shellcheck: eseguire con uv run ./scripts/validate.sh per averlo dal venv')
fi

if command -v vagrant >/dev/null; then
  for lab in */lab.json; do
    # È una verifica statica: non richiedere che il driver del provider sia
    # caricato sull'host che esegue lint o CI.
    (cd "$(dirname "$lab")" && vagrant validate --ignore-provider >/dev/null)
    lab_dir=$(dirname "$lab")
    manual_file=Vagrant.start
    [[ -f "$lab_dir/Vagrantfile.start" ]] && manual_file=Vagrantfile.start
    (cd "$lab_dir" && VAGRANT_VAGRANTFILE="$manual_file" vagrant validate --ignore-provider >/dev/null)
  done
  echo 'OK: vagrant validate su entrambi i percorsi di ogni laboratorio.'
else
  skipped+=('vagrant: validate non eseguito')
fi

if ((${#skipped[@]})); then
  printf 'SALTATO: %s\n' "${skipped[@]}"
fi
echo 'Controlli statici completati; nessuna VM avviata.'
