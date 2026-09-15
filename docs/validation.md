# Verifiche statiche dei laboratori

Eseguite il 15 settembre 2026 sulla macchina di sviluppo macOS ARM, senza
installare pacchetti host e senza avviare VM:

| Controllo | Esito |
| --- | --- |
| Sintassi Bash di tutti gli script | OK |
| ShellCheck di tutti gli script | OK |
| Sintassi dei Vagrantfile e Vagrant.start | OK |
| `vagrant validate`, Vagrant 2.4.9, undici laboratori e due percorsi | OK |
| Topologie: IP, MAC, risorse, box/ruoli, file locali | OK |
| Ruff, codice Python | OK |
| Mypy strict, codice Python e test | OK |
| Pytest, configurazioni, versioni e isolamento dei percorsi | 13 passed |
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

CloudStack 4.23, Proxmox VE 9.2 e PBS 4.2 sono selezionati nei file lab.json
e vincolati dai provisioner tramite APT. La disponibilità dei pacchetti è stata
controllata nei repository ufficiali; l'installazione nei guest non è stata eseguita.

I nuovi laboratori CloudStack HA richiedono assemblaggio manuale: verificare
in particolare la compatibilità dello schema CloudStack con MySQL Group
Replication e l'integrazione dello storage secondario. Il fencing dei nodi
VirtualBox resta da progettare e provare. ZSvirt richiede una box locale;
OpenStack richiede il deployment Kolla descritto nel proprio README.

I laboratori Kubernetes sono stati verificati staticamente. Non sono stati
eseguiti kubeadm, K3s, Cilium, failover VRRP/etcd o test dei workload sul Bosgame.
