# Verifiche della prima versione

Eseguite il 15 settembre 2026 sulla macchina di sviluppo macOS ARM, senza
installare pacchetti host e senza avviare VM:

| Controllo | Esito |
| --- | --- |
| Sintassi Bash di tutti gli script | OK |
| ShellCheck di tutti gli script | OK |
| Sintassi dei cinque Vagrantfile | OK |
| `vagrant validate`, Vagrant 2.4.9, cinque laboratori | OK |
| Topologie: IP, MAC, risorse, box/ruoli, file locali | OK |
| Ruff, codice Python | OK |
| Mypy strict, codice Python e test | OK |
| Pytest, cinque casi di configurazione errata | 5 passed |
| Bandit, strumenti Python | Nessun problema rilevato |
| Link locali dei README e runbook | OK |

Per Vagrant è stata usata una directory temporanea con `VAGRANT_HOME`, perché
il workspace di sviluppo non può scrivere nella configurazione globale
dell'utente. La validazione finale è passata senza modificarla.

Le box Bento amd64/versione dichiarata e gli indici repository host sono stati
consultati online. Queste verifiche non dimostrano che provisioning, driver
Ubuntu, nested KVM, cluster, HA, Ceph o restore funzionino end-to-end sull'hardware
destinazione. Eseguire la checklist in [troubleshooting.md](troubleshooting.md)
sul Bosgame prima di considerare collaudato ciascun laboratorio.
