# proxmox_3nodes_ceph

Per studiare tutto a mano usare `Vagrantfile.start` e seguire [STEPS.md](STEPS.md).
Il file basic dichiara le stesse box, VM, risorse, NIC, MAC e dischi del
`Vagrantfile`, ma non contiene alcun provisioner del guest.

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Nel percorso basic continuare con STEPS.md. Usare la variabile anche per
`status`, `ssh`, `halt`, `up` e `destroy`. I due file condividono `.vagrant`:
non alternarli sulle stesse istanze.

Versioni richieste: **Proxmox VE 9.2**.
Patch consentite nel ramo indicato; selezione in `lab.json` e pin APT nel guest.
Il percorso assistito richiede la box locale `local/proxmox-ve-9.2` versione
`0`, costruita e aggiunta seguendo [`create_boxes/proxmox`](../create_boxes/proxmox/README.md).
Anche il percorso manuale usa la stessa box, ma non esegue alcun provisioner:
identità PVE, reti, cluster e Ceph vengono configurati seguendo `STEPS.md`.

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
Gli indirizzi host-only sono raggiungibili dal Bosgame, non direttamente dagli
altri computer della LAN senza routing o tunnel attraverso il Bosgame.

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

Lo script clona la box PVE, sostituisce l'identità template con hostname, CA e
certificati specifici del nodo, configura le reti e infine esegue un reload.
Rifiuta la finalizzazione se trova cluster, VM o container preesistenti.
Leggere il [runbook locale](docs/proxmox.md) per
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
ripristinare il layout di base. Il collaudo end-to-end multinodo resta da
eseguire: sul mononodo di riferimento VirtualBox 7.2.18 con nested AMD-V ha
mostrato uno stall del clock dopo circa due minuti. Disabilitare
`virt-vmsave-vmload` non lo ha risolto; verificare stabilità e log VirtualBox
prima di creare cluster, OSD o guest annidati.

## Ceph

Seconda rete interna **10.58.1.0/24**, bridge `vmbr1`, con suffissi
.11/.12/.13. Public e replica Ceph condividono questo segmento; Corosync resta
su management. Seguire il [runbook Ceph locale](docs/ceph.md) per installazione,
MON/MGR, selezione dei dischi, pool RBD e prova di guasto.

Un disco raw da 100 GB per nodo è lasciato intatto dal provisioning. Non
assumere che si chiami /dev/sdb: identificarlo per dimensione e layout.

### Separazione dei traffici

Due reti del laboratorio: vmbr1 per Ceph (client/public e replica); vmbr0
per management, Corosync, migrazione, guest e backup. La NIC NAT tecnica
serve solo Vagrant/download. Non selezionare vmbr1 come rete di migrazione.
