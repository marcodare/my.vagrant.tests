# proxmox_3nodes_simple

Per studiare tutto a mano usare `Vagrantfile.start` e seguire [STEPS.md](STEPS.md).
Il `Vagrantfile` mantiene il percorso assistito già disponibile.

## Due percorsi di avvio

```bash
./scripts/up.sh                                          # assistito
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Nel percorso basic continuare con STEPS.md. Usare la variabile anche per
`status`, `halt` e `destroy`; non alternare i due file sulle stesse VM.

Versioni richieste: **Proxmox VE 9.2**.
Patch consentite nel ramo indicato; selezione in `lab.json` e pin APT nel guest.

Laboratorio autonomo Vagrant/VirtualBox. **Solo questo lab acceso**; spegnere
le altre infrastrutture prima di iniziare. Modificare liberamente `Vagrantfile`,
`lab.json` e gli script locali: non esistono import da altre cartelle.

## Topologia

| Nodo | Management | vCPU | RAM | Disco dati GB |
| --- | --- | --- | --- | --- |
| pve1 | 192.168.56.11 | 6 | 12 GiB | — |
| pve2 | 192.168.56.12 | 6 | 12 GiB | — |
| pve3 | 192.168.56.13 | 6 | 12 GiB | — |

Ogni nodo ha disco OS 80 GB e NIC NAT tecnica. Il bridge management `vmbr0`
usa 192.168.56.0/24 host-only, senza gateway. UI PVE:
https://192.168.56.11:8006, https://192.168.56.12:8006,
https://192.168.56.13:8006.

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
l'installazione di Proxmox. Leggere il [runbook comune](../docs/proxmox.md) per
verifica KVM, creazione del cluster, join, prima VM e migrazione.
In quel runbook sostituire `S` con **56**.

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

## Percorso di studio

1. Creare cluster e aggiungere manualmente i nodi; osservare quorum con 3/2 nodi.
2. Creare una VM e uno snapshot; clonare e ripristinare.
3. Migrare la VM a caldo includendo i dischi locali, osservando tempi e ping.
4. Studiare permessi, resource pool, task e log.
5. Osservare i servizi HA e i limiti del disco locale. Per il failover automatico
   con disco accessibile sul superstite passare al laboratorio Ceph.

Una sola rete del lab: management, Corosync, migrazione e guest condividono
vmbr0. La NIC NAT serve Vagrant e non è un secondo segmento didattico.
