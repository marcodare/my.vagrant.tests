# proxmox_3nodes_ceph

Laboratorio autonomo Vagrant/VirtualBox. **Solo questo lab acceso**; spegnere
le altre infrastrutture prima di iniziare. Modificare liberamente `Vagrantfile`,
`lab.json` e gli script locali: non esistono import da altre cartelle.

## Topologia

| Nodo | Management | vCPU | RAM | Disco dati GB |
| --- | --- | --- | --- | --- |
| pve1 | 192.168.58.11 | 6 | 16 GiB | 100 |
| pve2 | 192.168.58.12 | 6 | 16 GiB | 100 |
| pve3 | 192.168.58.13 | 6 | 16 GiB | 100 |

Ogni nodo ha disco OS 80 GB e NIC NAT tecnica. Il bridge management `vmbr0`
usa 192.168.58.0/24 host-only, senza gateway. UI PVE:
https://192.168.58.11:8006, https://192.168.58.12:8006,
https://192.168.58.13:8006.

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
In quel runbook sostituire `S` con **58**.

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

Seconda rete interna **10.58.1.0/24**, bridge `vmbr1`, con suffissi
.11/.12/.13. Public e replica Ceph condividono questo segmento; Corosync resta
su management. Seguire il [runbook Ceph locale](docs/ceph.md) per installazione,
MON/MGR, selezione dei dischi, pool RBD e prova di guasto.

Un disco raw da 100 GB per nodo è lasciato intatto dal provisioning. Non
assumere che si chiami /dev/sdb: identificarlo per dimensione e layout.
