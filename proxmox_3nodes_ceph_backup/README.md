# proxmox_3nodes_ceph_backup

Laboratorio autonomo Vagrant/VirtualBox. **Solo questo lab acceso**; spegnere
le altre infrastrutture prima di iniziare. Modificare liberamente `Vagrantfile`,
`lab.json` e gli script locali: non esistono import da altre cartelle.

## Topologia

| Nodo | Management | vCPU | RAM | Disco dati GB |
| --- | --- | --- | --- | --- |
| pve1 | 192.168.59.11 | 6 | 16 GiB | 100 |
| pve2 | 192.168.59.12 | 6 | 16 GiB | 100 |
| pve3 | 192.168.59.13 | 6 | 16 GiB | 100 |
| pbs1 | 192.168.59.20 | 4 | 8 GiB | 240 |

Ogni nodo ha disco OS 80 GB e NIC NAT tecnica. Il bridge management `vmbr0`
usa 192.168.59.0/24 host-only, senza gateway. UI PVE:
https://192.168.59.11:8006, https://192.168.59.12:8006,
https://192.168.59.13:8006.

## Avvio

Host Ubuntu 26.04 amd64 con VirtualBox 7.2 e Vagrant configurati dallo script
`configure.host.sh` nella radice del progetto. Questa cartella, dopo la
preparazione dell'host, può essere copiata ed eseguita da sola.

```bash
vagrant validate
./scripts/up.sh
vagrant ssh pve1
sudo passwd root
```

Ripetere `sudo passwd root` anche su pve2/pve3 e, se presente, pbs1. Accedere
alle UI con root e realm Linux PAM. Nessuna password è inclusa nel repository.

Lo script avvia Debian e installa il kernel PVE, esegue reload, poi completa
l'installazione di Proxmox. Leggere il [runbook locale](docs/proxmox.md) per
verifica KVM, creazione del cluster, join, prima VM e migrazione.
In quel runbook sostituire `S` con **59**.

## Stop e reset

Spegnere prima le VM interne e fermare le risorse HA come descritto nel runbook:

```bash
vagrant halt             # conserva tutti i dischi
vagrant up               # riavvio successivo
vagrant destroy          # distruttivo: elimina nodi, dischi e VM annidate
```

Dopo un destroy ripartire da `./scripts/up.sh`. `data/`, `disks/`, `logs/` sono
spazi locali esclusi da Git; i dischi del provider sono gestiti da VirtualBox.
Non rilanciare provisioning dopo modifiche didattiche alle reti senza voler
ripristinare il layout di base. Collaudo sul Bosgame ancora da eseguire.

## Ceph

Seconda rete interna **10.59.1.0/24**, bridge `vmbr1`, con suffissi
.11/.12/.13. Public e replica Ceph condividono questo segmento; Corosync resta
su management. Seguire il [runbook Ceph locale](docs/ceph.md) per installazione,
MON/MGR, selezione dei dischi, pool RBD e prova di guasto.

Un disco raw da 100 GB per nodo è lasciato intatto dal provisioning. Non
assumere che si chiami /dev/sdb: identificarlo per dimensione e layout.

## Proxmox Backup Server

PBS risponde su **https://192.168.59.20:8007**, con indirizzo storage
**10.59.1.20** su vmbr1. Ha 8 GiB RAM e un disco aggiuntivo da 240 GB.

1. `vagrant ssh pbs1`, poi `sudo passwd root`; accedere come root@pam.
2. In Administration → Disks identificare il disco **240 GB** non utilizzato.
   Creare un filesystem Directory ext4 con nome `backup`, selezionando
   l'opzione per creare il datastore. Questa operazione formatta il disco scelto.
3. Controllare Datastore → backup e prendere nota del fingerprint del server.
4. Nella UI PVE, Datacenter → Storage → Add → Proxmox Backup Server:
   ID `pbs-backup`, server **10.59.1.20**, datastore `backup`, fingerprint
   verificato dalla console PBS e credenziali root@pam impostate al punto 1.
   In seguito esercitarsi con utente/token dedicato e permessi sul datastore.
5. Eseguire un backup snapshot di VM 100 su pbs-backup. Verificare task concluso
   e snapshot presente nel datastore; eseguire anche un job Verify in PBS.
6. Ripristinare come **VM 200**, inizialmente con NIC scollegata per evitare
   conflitti IP/MAC. Avviare e controllare i dati; non sovrascrivere VM 100.
7. Configurare retention (es. keep-last=3), provare prune e poi garbage
   collection: sono operazioni diverse, lo spazio non si libera solo con prune.

Il traffico backup condivide la seconda rete con Ceph. Prima dello stop
attendere il completamento dei job. PBS sul medesimo host fisico è utile per
imparare backup/restore, ma non protegge dalla perdita dell'SSD del Bosgame.
