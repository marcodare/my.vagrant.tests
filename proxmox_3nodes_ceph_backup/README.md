# proxmox_3nodes_ceph_backup

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

Versioni richieste: **Proxmox VE 9.2** e **Proxmox Backup Server 4.2**.
Patch consentite nel ramo indicato; selezione in `lab.json` e pin APT nel guest.
Il percorso assistito usa `local/proxmox-ve-9.2` versione `0` per i tre PVE,
costruita e aggiunta seguendo [`create_boxes/proxmox`](../create_boxes/proxmox/README.md).
I tre PVE usano la stessa box anche nel percorso manuale, senza provisioner;
solo `pbs1` resta su Bento Debian 13 in entrambi i percorsi perché deve essere
installato come Proxmox Backup Server, non come Proxmox VE.

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

Lo script finalizza sui tre PVE identità, CA e certificati distinti dalla box,
configura le reti e installa PBS 4.2 sul quarto nodo Debian, quindi esegue un
reload. La finalizzazione PVE rifiuta cluster, VM o container preesistenti.
Leggere il [runbook locale](docs/proxmox.md) per
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
ripristinare il layout di base. Il collaudo end-to-end multinodo resta da
eseguire: sul mononodo di riferimento VirtualBox 7.2.18 con nested AMD-V ha
mostrato uno stall del clock dopo circa due minuti. Disabilitare
`virt-vmsave-vmload` non lo ha risolto; verificare stabilità e log VirtualBox
prima di creare cluster, OSD, datastore o guest annidati.

## Ceph

Seconda rete interna **10.59.1.0/24**, bridge `vmbr1`, con suffissi
.11/.12/.13. Public e replica Ceph condividono questo segmento; Corosync resta
su management. Seguire il [runbook Ceph locale](docs/ceph.md) per installazione,
MON/MGR, selezione dei dischi, pool RBD e prova di guasto.

Un disco raw da 100 GB per nodo è lasciato intatto dal provisioning. Non
assumere che si chiami /dev/sdb: identificarlo per dimensione e layout.

## Proxmox Backup Server

PBS risponde su **https://192.168.59.20:8007**, solo sulla rete principale vmbr0; non ha una NIC sulla rete Ceph. Ha 8 GiB RAM e un disco aggiuntivo da 240 GB.

1. `vagrant ssh pbs1`, poi `sudo passwd root`; accedere come root@pam.
2. In Administration → Disks identificare il disco **240 GB** non utilizzato.
   Creare un filesystem Directory ext4 con nome `backup`, selezionando
   l'opzione per creare il datastore. Questa operazione formatta il disco scelto.
3. Controllare Datastore → backup e prendere nota del fingerprint del server.
4. Nella UI PVE, Datacenter → Storage → Add → Proxmox Backup Server:
   ID `pbs-backup`, server **192.168.59.20**, datastore `backup`, fingerprint
   verificato dalla console PBS e credenziali root@pam impostate al punto 1.
   In seguito esercitarsi con utente/token dedicato e permessi sul datastore.
5. Eseguire un backup snapshot di VM 100 su pbs-backup. Verificare task concluso
   e snapshot presente nel datastore; eseguire anche un job Verify in PBS.
6. Ripristinare come **VM 200**, inizialmente con NIC scollegata per evitare
   conflitti IP/MAC. Avviare e controllare i dati; non sovrascrivere VM 100.
7. Configurare retention (es. keep-last=3), provare prune e poi garbage
   collection: sono operazioni diverse, lo spazio non si libera solo con prune.

Il traffico backup usa vmbr0 insieme a management, guest e migrazione.
vmbr1 è dedicato esclusivamente al traffico Ceph. Prima dello stop
attendere il completamento dei job. PBS sul medesimo host fisico è utile per
imparare backup/restore, ma non protegge dalla perdita dell'SSD del Bosgame.

### Separazione dei traffici

Due reti del laboratorio: vmbr1 per Ceph (client/public e replica); vmbr0
per management, Corosync, migrazione, guest e backup. La NIC NAT tecnica
serve solo Vagrant/download. Non selezionare vmbr1 come rete di migrazione.
