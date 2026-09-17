# Linux: quattro distribuzioni in rete

Laboratorio semplice per confrontare quattro distribuzioni Linux collegate da
una sola rete: quattro VM, 16 GiB RAM e nessun servizio applicativo aggiunto.
Il percorso assistito installa soltanto chrony e strumenti di amministrazione.
Serve per esercizi di rete, pacchetti, firewall, SELinux/AppArmor, SSH e
confronto fra famiglie Debian ed Enterprise Linux.

| Nodo | Sistema | Box Bento | Rete del lab |
| --- | --- | --- | --- |
| ubuntu24 | Ubuntu 24.04 LTS | `bento/ubuntu-24.04` 202510.26.0 | 192.168.66.11 |
| rocky9 | Rocky Linux 9 | `bento/rockylinux-9` 202510.26.0 | 192.168.66.12 |
| ubuntu26 | Ubuntu 26.04 LTS | `bento/ubuntu-26.04` 202606.01.0 | 192.168.66.13 |
| rocky10 | Rocky Linux 10 | `bento/rockylinux-10` 202510.26.0 | 192.168.66.14 |

Ogni nodo ha 2 vCPU, 4 GiB RAM e disco OS da 80 GB. NIC 1 è NAT per `vagrant
ssh` e download; NIC 2 è la rete host-only `192.168.66.0/24`, raggiungibile
dal Bosgame ma non direttamente dagli altri computer della LAN senza routing o
tunnel attraverso il Bosgame. Non ci sono reti interne né virtualizzazione
annidata.

Le box hanno versioni diverse perché non esiste una release Bento comune:
Ubuntu 26.04 è pubblicata solo dalla 202606.01.0. Ogni box è fissata per nodo
in `lab.json` e il validatore rifiuta versioni diverse. Il byte MAC del lab è
`72` (`mac_id`): `66` è già usato dal laboratorio k3s e 72 sta fuori dal pool
host-only 56–71, così nessun futuro lab lo erediterà per default.

## Due percorsi di avvio

```bash
./scripts/up.sh                                          # assistito
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh rocky10
```

Il `Vagrantfile` imposta hostname, `/etc/hosts`, l'IP sulla NIC del lab, NTP e
alcuni strumenti di rete (`tcpdump`, `iperf3`, `traceroute`, `nc`, `dig`).
`Vagrantfile.start` usa la stessa definizione di VM, NIC, MAC, risorse e disco,
ma non dichiara gli script di provisioning: la NIC del lab resta quindi senza
indirizzo e la configurazione è l'esercizio descritto in [STEPS.md](STEPS.md).
Usare la variabile anche per `status`, `ssh`, `halt`, `up` e `destroy`. I due
file condividono `.vagrant`: non alternarli sulle stesse istanze.

## Operazioni

```bash
vagrant status
vagrant ssh ubuntu24            # oppure rocky9, ubuntu26, rocky10
vagrant halt                    # conserva lo stato su disco
vagrant up                      # riprende le VM già configurate
vagrant destroy                 # reset distruttivo, chiede conferma
```

Prima di avviare questo lab spegnere quello attivo: una sola infrastruttura
accesa alla volta.

### Guest Additions e ripresa dopo un avvio interrotto

Le box contengono già le Guest Additions e il lab non usa cartelle sincronizzate.
Entrambi i Vagrantfile disabilitano quindi l'aggiornamento automatico se rilevano
il plugin opzionale `vagrant-vbguest`: una differenza fra la versione VirtualBox
dell'host e quella inclusa nella box può produrre un avviso, ma non blocca il
lab.

Se un precedente `vagrant up` si è fermato durante l'installazione di
`linux-headers-$(uname -r)` con errori APT `404 Not Found`, non serve distruggere
la VM. Rieseguire dallo stesso percorso:

```bash
./scripts/up.sh
```

Vagrant riprende la macchina già creata, esegue i provisioner del lab e continua
con gli altri nodi. Il plugin non è richiesto da questo repository; può anche
essere rimosso globalmente con `vagrant plugin uninstall vagrant-vbguest`, ma la
configurazione del lab non lo richiede.

## Esercizi suggeriti

- Confrontare `ip`, netplan e NetworkManager; `apt` e `dnf`; `ufw` e `firewalld`.
- Misurare la banda fra nodi con `iperf3` e osservarla con `tcpdump`.
- Su Rocky esaminare SELinux (`getenforce`, `ausearch`); su Ubuntu AppArmor.
- Scambiare chiavi SSH fra nodi e provare `rsync` fra distribuzioni.
- Confrontare versioni di kernel, systemd, OpenSSL e Python fra 24.04/9 e 26.04/10.

## Limiti

- Rocky Linux 10 richiede CPU x86-64-v3: il Ryzen AI Max+ 395 la soddisfa, ma
  su host più vecchi la VM non avvia.
- Su Rocky `firewalld` è attivo come da box: ICMP e SSH passano, altri servizi
  vanno aperti esplicitamente (vedere STEPS.md).
- Il disco OS viene esteso a 80 GB da Vagrant, ma la crescita di partizione e
  filesystem nel guest non è automatica: verificare con `lsblk` e `df -h`.
- Nessuna prova end-to-end è stata eseguita: le verifiche sono solo statiche
  finché il lab non viene collaudato sul Bosgame.
