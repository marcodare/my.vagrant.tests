# Percorso manuale: Proxmox con Ceph

`Vagrantfile.start` clona `local/proxmox-ve-9.2` e crea NIC e dischi, senza
provisioning del guest. PVE 9.2 è già presente; identità dei nodi, rete,
cluster e Ceph sono l'esercizio. Su VM generiche o bare metal partire da PVE
9.2 standalone, oppure installarlo su Debian 13 seguendo
[docs/proxmox.md](docs/proxmox.md). Non usare mai il disco OS come OSD.

## 1. Avvio, inventario e identità

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Su ciascun nodo verificare `pveversion`, un kernel `-pve`, assenza di
`/etc/pve/corosync.conf` e assenza di guest. Identificare NIC e disco OSD
tramite MAC e seriale dichiarati in `lab.json`, usando `ip -o link`, `lsblk -o
NAME,SIZE,TYPE,SERIAL,MOUNTPOINTS` e `wipefs -n <DISCO>`.

Rimuovere da `/etc/hosts` la riga del template e aggiungere:

```text
192.168.58.11 pve1.lab.test pve1
192.168.58.12 pve2.lab.test pve2
192.168.58.13 pve3.lab.test pve3
```

Su ogni clone vuoto impostare `NODE` al nome corretto e rigenerare lo stato
standalone prima di qualsiasi cluster o guest:

```bash
NODE=pve1  # usare pve2 e pve3 sugli altri nodi
sudo test ! -e /etc/pve/corosync.conf
sudo find /etc/pve/nodes -type f \
  \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -print
# Il comando precedente non deve produrre output.
sudo systemctl stop pve-ha-lrm pve-ha-crm pvescheduler \
  pvestatd pveproxy pvedaemon
sudo systemctl stop pve-cluster
if mountpoint -q /etc/pve; then echo '/etc/pve ancora montato'; exit 1; fi
sudo rm -f /var/lib/pve-cluster/config.db /var/lib/pve-cluster/config.db-*
sudo hostnamectl set-hostname "$NODE"
sudo systemctl start pve-cluster
sudo pvecm updatecerts --force
sudo systemctl start pvedaemon pveproxy pvestatd pvescheduler \
  pve-ha-crm pve-ha-lrm
sudo test -d "/etc/pve/nodes/$NODE"
```

La rimozione di `config.db` vale esclusivamente per i cloni standalone vuoti
della box. Non applicarla a nodi configurati o a installazioni generiche già
correttamente inizializzate.

## 2. Rete e cluster PVE

Installare `ifupdown2 isc-dhcp-client chrony`. Mantenere la NIC NAT in DHCP,
senza spostarne la default route. Creare:

| Bridge | Rete | Uso |
| --- | --- | --- |
| `vmbr0` | `192.168.58.11-.13/24` | management e Corosync |
| `vmbr1` | `10.58.1.11-.13/24` | Ceph public e cluster network |

`vmbr1` non deve avere gateway. Dopo `sudo ifreload -a`, controllare indirizzi,
route, DNS, NTP e connettività completa tra i tre nodi su entrambe le reti.
Creare quindi il cluster `study` su `pve1` e aggiungere gli altri nodi:

```bash
# pve1
sudo pvecm create study --link0 192.168.58.11

# pve2/pve3; sostituire con il proprio indirizzo management
sudo pvecm add 192.168.58.11 --link0 <IP_MANAGEMENT_DEL_NODO>

sudo pvecm status
```

## 3. Creare Ceph

Installare dalla UI o dalla CLI PVE la release Ceph proposta e supportata da
PVE 9.2. Inizializzare Ceph su `pve1` indicando `10.58.1.0/24` sia come public
sia come cluster network. Creare tre MON, almeno due MGR e un OSD per ciascun
disco dati da 100 GB, dopo un'ultima verifica del device.

Creare un pool replicato con `size=3` e `min_size=2`, aggiungerlo come storage
RBD condiviso e collocarvi una VM di prova. Prima dei fault test controllare:

```bash
sudo ceph -s
sudo ceph osd tree
sudo ceph osd pool ls detail
pvesm status
```

Lo stato iniziale deve essere `HEALTH_OK`, tutti gli OSD `up/in` e lo storage
visibile dai tre nodi.

## 4. Migrazione e fault test

Migrare a caldo la VM e verificare che continui ad accedere al disco RBD.
Spegnere un solo nodo alla volta, osservare quorum PVE, stato Ceph e degrado
delle repliche, quindi attendere il ritorno a `HEALTH_OK` prima del test
successivo. Provare HA soltanto dopo aver compreso quorum e fencing; non
forzare il quorum con `pvecm expected`. I controlli di dettaglio sono in
[docs/ceph.md](docs/ceph.md).

Per eliminare l'ambiente manuale usare la stessa variabile:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```
