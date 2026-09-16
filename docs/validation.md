# Verifiche statiche dei laboratori

Eseguite il 15 settembre 2026 sul Bosgame (Ubuntu 26.04.1 amd64), senza
installare pacchetti host e senza avviare VM:

| Controllo | Esito |
| --- | --- |
| Sintassi Bash di tutti gli script | OK |
| ShellCheck di tutti gli script | OK |
| Sintassi dei Vagrantfile e Vagrant.start | OK |
| `vagrant validate`, Vagrant 2.4.9, tredici laboratori e due percorsi | OK |
| Topologie: IP, MAC, risorse, box/ruoli, file locali | OK |
| Ruff, codice Python | OK |
| Mypy strict, codice Python e test | OK |
| Pytest, configurazioni, versioni e isolamento dei percorsi | 24 passed |
| Bandit, strumenti Python | Nessun problema rilevato |
| Link locali dei README e runbook | OK |

`./scripts/validate.sh` salta e riepiloga gli strumenti assenti invece di
interrompersi: prima un `ruby` mancante fermava lo script prima di
`check_layout.py`, shellcheck e `vagrant validate`.

I controlli statici ora coprono anche gli errori che si manifestavano solo
all'avvio: segmenti host-only fuori dal pool accettato da VirtualBox, porte host
duplicate fra laboratori, indirizzi ripetuti a mano nei Vagrantfile invece di
essere letti da `lab.json`, e la raggiungibilità dichiarata dell'API Kubernetes.

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
Restano da provare sul campo anche il port forward dell'API, l'accesso `kubectl`
dal Mac e la validità delle SAN del certificato: la configurazione è dichiarata e
coerente, ma non è stata esercitata su un cluster acceso.

Il laboratorio `linux_4nodes` (Ubuntu 24.04/26.04, Rocky Linux 9/10) è stato
aggiunto il 15 settembre 2026 con sole verifiche statiche: box e versioni
controllate sul registro Vagrant, `vagrant validate` su entrambi i percorsi,
provisioner sottoposti a shellcheck. Non sono stati provati sul Bosgame l'avvio
delle box Rocky, la configurazione NetworkManager via `nmcli` e l'estensione
del disco OS a 80 GB sulle quattro distribuzioni.

Il laboratorio `opnsense_4nodes_networks` (OPNsense 26.1 da `bento/freebsd-14.3`
con `opnsense-bootstrap`, quattro Debian 13 su tre segmenti) è stato aggiunto il
15 settembre 2026 con sole verifiche statiche: box e rami controllati sul
registro Vagrant e su pkg.opnsense.org, `vagrant validate` su entrambi i
percorsi, shellcheck, e generazione della `config.xml` provata a secco con
funzioni FreeBSD simulate (XML ben formato, interfacce e regole attese). Non
sono stati provati sul Bosgame il bootstrap reale, il riavvio in OPNsense,
`vagrant ssh` attraverso la WAN e le rotte dei Debian.
