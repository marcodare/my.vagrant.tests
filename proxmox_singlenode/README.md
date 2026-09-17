# proxmox_singlenode

Laboratorio minimale con un solo nodo **Proxmox VE 9.2 standalone**. Serve a
isolare i problemi di avvio, rete, storage e virtualizzazione annidata senza
introdurre cluster, quorum, Corosync, Ceph o migrazioni.

Per studiare ogni passaggio usare `Vagrantfile.start` e seguire
[STEPS.md](STEPS.md). Il `Vagrantfile` offre invece il percorso assistito che
finalizza il clone PVE, configura il bridge e verifica il nodo.

## Topologia e risorse

| Nodo | Ruolo | Management | vCPU | RAM | Disco OS |
| --- | --- | --- | --- | --- | --- |
| `pve1` | PVE standalone | `192.168.68.11/24` | 6 | 12 GiB | 80 GB dinamico |

La NIC 1 è una NAT tecnica per `vagrant ssh`, APT, DNS e NTP. La NIC 2 ha MAC
`08:00:27:44:01:02` ed è collegata alla rete host-only `192.168.68.0/24`;
nel guest diventa la porta di `vmbr0`. Il bridge non ha gateway: le VM annidate
possono comunicare con il Bosgame sul segmento, ma non hanno Internet senza un
router/NAT aggiunto esplicitamente.

UI PVE: `https://192.168.68.11:8006`. Il certificato è autofirmato.
La rete è host-only: l'indirizzo è raggiungibile dal Bosgame, non direttamente
dagli altri computer della LAN. Da remoto usare routing esplicito oppure un
tunnel SSH verso il Bosgame.

## Prerequisiti

- host Ubuntu 26.04 amd64 preparato con `../configure.host.sh`;
- VirtualBox 7.2, Vagrant e SVM/AMD-V disponibili;
- nessun altro laboratorio acceso;
- box locale `local/proxmox-ve-9.2` versione `0`, costruita seguendo
  [`create_boxes/proxmox`](../create_boxes/proxmox/README.md).

La box contiene già Proxmox VE e il kernel PVE, ma non contiene cluster, guest
o configurazioni didattiche. Il laboratorio non scarica né costruisce la box.

## Percorso assistito

```bash
vagrant validate
./scripts/up.sh
vagrant ssh pve1
```

`scripts/up.sh` controlla la presenza della box, esegue `vagrant up` e poi
`vagrant reload` per attivare il nuovo layout di rete. Il provisioning:

- rigenera identità `pmxcfs`, CA e certificati del clone;
- configura hostname, `/etc/hosts`, chrony, NAT e `vmbr0`;
- verifica PVE 9.2, kernel PVE, `/dev/kvm` e storage locali;
- lascia il nodo standalone e non crea VM o container.

Impostare una password root soltanto in modo interattivo:

```bash
vagrant ssh pve1
sudo passwd root
```

Accedere alla UI come `root` nel realm **Linux PAM**. Nessuna password è
contenuta nel repository.

## Percorso basic/manuale

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Questo percorso usa la stessa definizione di VM, NIC, MAC, risorse e disco del
percorso assistito, ma non dichiara gli script di provisioning. Non imposta
quindi hostname o IP nel guest. Continuare con [STEPS.md](STEPS.md) e mantenere
la variabile in tutti i comandi `status`, `ssh`, `halt`, `up` e `destroy`.

Non alternare i due Vagrantfile sulle stesse istanze. Per cambiare percorso,
distruggere esplicitamente l'istanza con lo stesso `VAGRANT_VAGRANTFILE` usato
per crearla e solo dopo avviare l'altro percorso.

## Verifiche rapide

Nel nodo:

```bash
hostname --fqdn
uname -r
test -c /dev/kvm && echo KVM_OK
ip -br address
ip route
sudo pveversion
sudo pvesm status
sudo test ! -e /etc/pve/corosync.conf
```

Il risultato atteso è `pve1.lab.test`, kernel con suffisso `-pve`,
`192.168.68.11/24` su `vmbr0`, default route sulla NAT, storage `local` e
normalmente `local-lvm`, nessuna configurazione Corosync.

## Arresto e reset

Spegnere prima tutte le VM e i container annidati, poi dalla cartella del lab:

```bash
vagrant halt       # conserva nodo e dischi
vagrant up         # riprende il nodo esistente
vagrant destroy    # distruttivo: elimina anche i guest annidati
```

Nel percorso manuale anteporre sempre
`VAGRANT_VAGRANTFILE=Vagrantfile.start`. Dopo `destroy`, il percorso assistito
riparte con `./scripts/up.sh`.

## Limiti

- Un nodo standalone non offre quorum, migrazione, HA o ridondanza.
- Gli storage locali risiedono sullo stesso disco virtuale e sullo stesso SSD
  fisico del Bosgame: snapshot e backup locali non proteggono dal suo guasto.
- Il fencing hardware non è disponibile. Nei cloni VirtualBox `softdog` è reso
  diagnostico per evitare reset causati da pause del guest.
- La virtualizzazione è annidata (`VirtualBox -> PVE/KVM -> guest`): prestazioni
  e timing non rappresentano il bare metal.
- Il percorso assistito ha completato provisioning, reload, rete, `/dev/kvm`,
  storage e UI, ma con VirtualBox 7.2.18 e nested AMD-V il clock si è poi
  bloccato dopo circa due minuti (`TM: Giving up catch-up attempt`). Il test con
  `virt-vmsave-vmload=off` non ha risolto; con nested AMD-V disabilitato il boot
  resta stabile ma `/dev/kvm` scompare. Il lab non è quindi ancora dichiarato
  operativo per VM annidate su questa combinazione host/hypervisor.

`data/`, `disks/` e `logs/` sono spazi locali esclusi da Git. I dischi gestiti
da Vagrant restano nella directory del provider e non vanno spostati a mano.
