# Percorso manuale: Proxmox con Ceph

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant preparare tre Debian 13 amd64 con virtualizzazione hardware,
una NIC management, una NIC Ceph e un disco dati vuoto dedicato per nodo.
Sostituire IP/device dopo averli inventariati; non usare mai il disco OS come
OSD. Servono hostname/DNS stabili, NTP, accesso ai repository e console remota.
Su hardware reale separare failure domain, alimentazione e storage fisico.

1. Avviare `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. Configurare Proxmox
   VE 9.2, cluster, hostname e vmbr0 `192.168.58.11-.13/24` seguendo
   [docs/proxmox.md](docs/proxmox.md).
2. Configurare `vmbr1` esclusivamente per Ceph con `10.58.1.11-.13/24`, senza
   gateway. Verificare che il secondo disco raw da 100 GB sia vuoto con `lsblk`.
3. Installare i pacchetti Ceph compatibili dalla UI/CLI PVE. Inizializzare Ceph
   su pve1 indicando public e cluster network `10.58.1.0/24`, creare tre MON,
   almeno due MGR e un OSD per ciascun disco dati.
4. Creare pool replicato size 3/min_size 2, aggiungerlo come RBD condiviso e
   collocarvi una VM. Verificare health, CRUSH e replica prima dei fault test.
5. Migrare a caldo la VM, spegnere un nodo alla volta e provare HA solo dopo
   aver compreso quorum e fencing. Seguire i controlli in [docs/ceph.md](docs/ceph.md).
