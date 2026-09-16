# proxmox_3nodes_networks

Per studiare tutto a mano usare `Vagrantfile.start` e seguire [STEPS.md](STEPS.md).
Il `Vagrantfile` mantiene il percorso assistito già disponibile.

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Nel percorso basic continuare con STEPS.md. Usare la variabile anche per
`status`, `halt` e `destroy`; non alternare i due file sulle stesse VM.

Versioni richieste: **Proxmox VE 9.2**.
Patch consentite nel ramo indicato; selezione in `lab.json` e pin APT nel guest.
Il percorso assistito richiede la box locale `local/proxmox-ve-9.2` versione
`0`, costruita e aggiunta seguendo [`create_boxes/proxmox`](../create_boxes/proxmox/README.md).
Anche il percorso manuale usa la stessa box, ma non esegue alcun provisioner:
identità PVE, reti e cluster vengono configurati seguendo `STEPS.md`.

Laboratorio autonomo Vagrant/VirtualBox. **Solo questo lab acceso**; spegnere
le altre infrastrutture prima di iniziare. Modificare liberamente `Vagrantfile`,
`lab.json` e gli script locali: non esistono import da altre cartelle.

## Topologia

| Nodo | Management | vCPU | RAM | Disco dati GB |
| --- | --- | --- | --- | --- |
| pve1 | 192.168.57.11 | 6 | 12 GiB | — |
| pve2 | 192.168.57.12 | 6 | 12 GiB | — |
| pve3 | 192.168.57.13 | 6 | 12 GiB | — |

Ogni nodo ha disco OS 80 GB e NIC NAT tecnica. Il bridge management `vmbr0`
usa 192.168.57.0/24 host-only, senza gateway. UI PVE:
https://192.168.57.11:8006, https://192.168.57.12:8006,
https://192.168.57.13:8006.

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
In quel runbook sostituire `S` con **57**.

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

## Reti ed esercizi

| Bridge | Rete | Uso |
| --- | --- | --- |
| vmbr0 | 192.168.57.0/24 | management e Corosync |
| vmbr1 | 10.57.1.0/24 | migrazione dedicata |
| vmbr2 | 10.57.2.0/24 | guest, VLAN e isolamento |

Le reti vmbr1/vmbr2 sono internal network VirtualBox condivise solo dai tre
nodi di questo lab. Gli IP dei nodi terminano in .11/.12/.13 su tutte le reti.

1. Verificare ping tra gli IP 10.57.1.11/12/13 e 10.57.2.11/12/13.
2. In Datacenter → Options → Migration Settings selezionare rete
   **10.57.1.0/24** e migrazione secure. Migrare una VM e osservare contatori
   `ip -s link show vmbr1`.
3. Collegare due VM, su nodi diversi, a vmbr2 con VLAN tag **100**. Assegnare
   172.20.100.11/24 e 172.20.100.12/24, senza gateway: verificare ping.
4. Cambiare tag di una VM a **200**, mantenendo per il test gli stessi IP:
   verificare isolamento. Per comunicare tra VLAN occorre un router.
5. Aggiungere un secondo link Corosync solo come esercizio successivo dopo
   avere studiato la configurazione; la base mantiene Corosync su management.

Nessun routing o DHCP automatico sulle reti aggiuntive. I tag non vanno
configurati anche dentro la VM quando è Proxmox ad applicarli sulla NIC.
