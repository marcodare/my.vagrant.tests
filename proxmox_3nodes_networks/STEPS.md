# Percorso manuale: Proxmox e reti

`Vagrantfile.start` usa le stesse box, VM, risorse, NIC, MAC e dischi del
percorso assistito, ma non dichiara provisioner nel guest. PVE e il kernel sono
già installati; hostname, identità `pmxcfs`, bridge, cluster e servizi di lab
restano da configurare a mano.

Su VM generiche o bare metal partire da tre installazioni PVE 9.2 standalone.
Se si parte da Debian 13 pulita, installare prima PVE seguendo la procedura
ufficiale indicata in [docs/proxmox.md](docs/proxmox.md). Adattare IP, MAC, nomi
delle NIC e gateway; mantenere accesso console, DNS e NTP funzionanti.

## 1. Avvio e inventario

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Usare la variabile per ogni comando del percorso manuale. I due file condividono
la directory `.vagrant`: senza la variabile Vagrant può caricare il percorso
assistito e applicare i suoi provisioner alle stesse VM. Su ciascun nodo:

```bash
pveversion
uname -r
hostname -s
sudo test ! -e /etc/pve/corosync.conf
sudo find /etc/pve/nodes -type f \
  \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -print
ip -br link
ip route
lsblk
```

Con la box locale sono attesi hostname `proxmox-template`, kernel `-pve`,
assenza di Corosync e nessuna configurazione guest. Identificare sempre le NIC
tramite i MAC dichiarati in `lab.json`, non tramite nomi come `enp0s8`.

## 2. Finalizzare l'identità dei cloni

Prima di creare rete o cluster, rimuovere da `/etc/hosts` l'eventuale riga del
template e aggiungere su tutti i nodi:

```text
192.168.57.11 pve1.lab.test pve1
192.168.57.12 pve2.lab.test pve2
192.168.57.13 pve3.lab.test pve3
```

Poi, un nodo alla volta, impostare `NODE=pve1`, `pve2` o `pve3` ed eseguire:

```bash
NODE=pve1  # usare pve2 e pve3 sugli altri nodi
sudo test ! -e /etc/pve/corosync.conf
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
sudo test ! -e /etc/pve/nodes/proxmox-template
```

Azzerare `config.db` è sicuro soltanto su questi cloni standalone vuoti. Non
farlo mai su un nodo già configurato, con guest o appartenente a un cluster.

Sui cloni VirtualBox, con i servizi HA fermi, rendere solo diagnostico il
watchdog `softdog` (timeout 10 s, che resetta il guest se il host lo congela
più a lungo): `options softdog soft_noboot=1` in
`/etc/modprobe.d/infra-lab-softdog.conf`; fermare prima `pve-ha-lrm`,
`pve-ha-crm` e `watchdog-mux`, ricaricare `softdog`, riavviare `watchdog-mux` e
attendere in `dmesg` `soft_noboot=1`, quindi riavviare i due servizi HA. Il
fencing resta un esercizio di comportamento; vedere
`proxmox_3nodes_simple/STEPS.md`.
Su un'installazione PVE generica già correttamente nominata non serve.

## 3. Costruire le reti

Installare `ifupdown2`, `isc-dhcp-client` e `chrony`. Portare la prima NIC
NAT in DHCP: serve a Vagrant per SSH e al guest per repository, DNS e NTP.
Nella box locale la NIC NAT è inizialmente la porta di un `vmbr0` statico creato dall'installer ISO (`bridge link` la mostra): il file `/etc/network/interfaces` va riscritto per intero.
Creare poi, senza gateway:

| Bridge | Rete | Uso |
| --- | --- | --- |
| `vmbr0` | `192.168.57.11-.13/24` | management e Corosync |
| `vmbr1` | `10.57.1.11-.13/24` | migrazione |
| `vmbr2` | `10.57.2.11-.13/24` | traffico guest/VLAN |

Associare ogni bridge alla NIC corretta tramite MAC. Rendere `vmbr2`
VLAN-aware; non aggiungere default route ai bridge. Applicare un nodo alla
volta con accesso console disponibile, quindi verificare:

```bash
command -v dhclient
sudo ifreload -a
ip -br address
ip route
getent hosts pve1 pve2 pve3
chronyc tracking
```

## 4. Cluster e verifiche

Creare `study` su `pve1` usando `vmbr0`, quindi aggiungere `pve2` e `pve3`.
Prima del join i nodi aggiunti devono essere privi di guest.

Prima del cluster lasciare i nodi accesi per alcuni minuti e verificare più
volte SSH, data e UI. Sul mononodo di riferimento VirtualBox 7.2.18 con nested
AMD-V ha prodotto `TM: Giving up catch-up attempt` e uno stall di circa 60
secondi. `virt-vmsave-vmload=off` non ha risolto; nested AMD-V disabilitato
elimina `/dev/kvm` e non è una soluzione valida. Fermarsi e conservare
`VBox.log` se il difetto ricompare.

```bash
# pve1
sudo pvecm create study --link0 192.168.57.11

# pve2 e pve3; verificare il fingerprint quando richiesto
sudo pvecm add 192.168.57.11 --link0 <IP_MANAGEMENT_DEL_NODO>

sudo pvecm status
sudo pvecm nodes
```

Nelle Datacenter Options selezionare `10.57.1.0/24` come migration network.
Creare VLAN e VM di prova su `vmbr2`, verificando tagging, isolamento e MTU.
Migrare una VM e controllare con `tcpdump` che il traffico passi da `vmbr1`.

## 5. Fault test e chiusura

Interrompere una sola rete alla volta: prima migrazione, poi guest, infine
management/Corosync. Annotare quali funzioni degradano e verificare il quorum
prima di ogni operazione. Ripristinare la rete prima del test successivo; non
usare `pvecm expected` per aggirare una perdita di quorum.

Prima di passare al `Vagrantfile` assistito distruggere esplicitamente le VM
manuali usando ancora `VAGRANT_VAGRANTFILE=Vagrantfile.start`. Solo dopo il
destroy avviare il percorso assistito senza la variabile.
