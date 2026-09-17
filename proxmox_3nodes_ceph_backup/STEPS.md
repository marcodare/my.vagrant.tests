# Percorso manuale: Proxmox, Ceph e PBS

`Vagrantfile.start` crea i tre nodi PVE dalla box `local/proxmox-ve-9.2` e
`pbs1` da Debian 13: PBS è un prodotto distinto e non deve derivare dalla box
PVE. Il file crea soltanto VM, NIC e dischi; identità, rete, cluster, Ceph e
backup restano manuali.

Su VM generiche o bare metal usare tre installazioni PVE 9.2 standalone e un
host Debian 13 pulito per PBS. Adattare IP, NIC, dischi e gateway, mantenendo
DNS, NTP e console. Il PBS reale dovrebbe stare in un failure domain distinto.

## 1. Avvio e inventario

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pbs1
```

Usare la variabile per tutti i comandi. Sui PVE verificare `pveversion`, kernel
`-pve`, assenza di Corosync e guest; su PBS verificare Debian 13. Inventariare
NIC via MAC e dischi via seriale con `ip -o link` e:

```bash
lsblk -o NAME,SIZE,TYPE,SERIAL,MOUNTPOINTS
sudo wipefs -n <DISCO_DATI>
```

Ogni PVE deve avere un disco OSD vuoto da 100 GB; PBS un disco datastore vuoto
da 240 GB. Non inizializzare mai un device finché seriale e ruolo non coincidono.

## 2. Finalizzare i tre cloni PVE

Rimuovere da `/etc/hosts` la riga del template e aggiungere su tutti i nodi:

```text
192.168.59.11 pve1.lab.test pve1
192.168.59.12 pve2.lab.test pve2
192.168.59.13 pve3.lab.test pve3
192.168.59.20 pbs1.lab.test pbs1
```

Su ogni clone PVE vuoto impostare `NODE=pve1`, `pve2` o `pve3`:

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

Questo reset è ammesso solo sui cloni standalone vuoti della box. Non usarlo
su nodi configurati. Su `pbs1` impostare normalmente hostname `pbs1`; non
esistono `pmxcfs` o certificati PVE da azzerare.

Sui cloni VirtualBox, con i servizi HA fermi, rendere solo diagnostico il
watchdog `softdog` (timeout 10 s, che resetta il guest se il host lo congela
più a lungo): `options softdog soft_noboot=1` in
`/etc/modprobe.d/infra-lab-softdog.conf`, poi `systemctl stop watchdog-mux`,
`modprobe -r softdog`, `systemctl start watchdog-mux`. Il fencing HA resta un
esercizio di comportamento; vedere `proxmox_3nodes_simple/STEPS.md`.

## 3. Reti e cluster

Prima del passaggio a `ifupdown2`, installare anche `isc-dhcp-client` e
`chrony`. Portare la NIC NAT in DHCP: sui nodi PVE della box locale è
inizialmente la porta di un `vmbr0` statico creato dall'installer ISO, quindi
`/etc/network/interfaces` va riscritto per intero; su `pbs1` (Debian) è già
in DHCP. Configurare senza gateway:

| Nodi | Bridge/rete | Uso |
| --- | --- | --- |
| PVE | `vmbr0`, `192.168.59.11-.13/24` | management/Corosync |
| PVE | `vmbr1`, `10.59.1.11-.13/24` | Ceph |
| PBS | management, `192.168.59.20/24` | UI e backup |

PBS non ha una NIC sulla rete Ceph. Verificare DHCP NAT, default route, DNS,
NTP e raggiungibilità management. Creare `study` su `pve1`, aggiungere `pve2`
e `pve3`, quindi controllare `pvecm status` prima di procedere.

## 4. Ceph

Installare la release Ceph supportata da PVE 9.2. Inizializzarla con public e
cluster network `10.59.1.0/24`, creare tre MON, almeno due MGR e un OSD per
ciascun disco da 100 GB. Creare un pool RBD con `size=3`, `min_size=2` e una VM
di prova. Attendere `ceph -s` in `HEALTH_OK` e tutti gli OSD `up/in`.

## 5. Proxmox Backup Server

Su `pbs1` installare Proxmox Backup Server 4.2 dai repository ufficiali,
riavviare sul kernel previsto e verificare i servizi. Inizializzare il disco da
240 GB soltanto dopo il controllo del seriale; creare filesystem, mount
persistente e datastore. Non salvare credenziali nel repository.

Aggiungere PBS al datacenter PVE usando `192.168.59.20`, fingerprint TLS
verificato e credenziali inserite interattivamente. Configurare job, retention,
prune e garbage collection, poi eseguire un backup e un restore come nuova VM.
Completare con una verifica file-level.

## 6. Fault test e limiti

Spegnere un solo PVE alla volta e osservare quorum, degrado Ceph e continuità
dei backup. Ripristinarlo e attendere il ritorno a `HEALTH_OK` prima di
continuare. La perdita fisica del Bosgame non è un test valido di disaster
recovery: in questo lab cluster e PBS risiedono sullo stesso host.

Per eliminare il percorso manuale:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```
