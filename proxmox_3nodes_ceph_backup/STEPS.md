# Percorso manuale: Proxmox, Ceph e PBS

## Uso su Vagrant, VM generiche o bare metal

La guida vale anche con tre host PVE Debian 13 e un host PBS Debian 13 esterni
a Vagrant. Ogni PVE richiede NIC management, NIC Ceph e disco OSD vuoto; PBS
richiede management e un disco datastore vuoto, senza accesso alla rete Ceph.
Adattare IP/device, mantenere DNS e NTP stabili e verificare sempre il seriale
dei dischi prima di inizializzarli. Un PBS reale va posto in un failure domain separato.

1. Avviare con `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. Sui tre PVE
   configurare Proxmox VE 9.2, cluster, vmbr0 `192.168.59.11-.13/24` e rete
   Ceph esclusiva `10.59.1.11-.13/24`; seguire [docs/ceph.md](docs/ceph.md).
   Su tutti i nodi che passano a `ifupdown2`, incluso PBS, installare prima
   `ifupdown2 isc-dhcp-client`: su Debian 13 il client DHCP è solo suggerito.
   Conservare la NIC NAT su DHCP e verificare `command -v dhclient`, indirizzo
   NAT, default route e risoluzione DNS dopo il riavvio.
2. Verificare e inizializzare i tre dischi OSD da 100 GB, quindi costruire pool
   RBD replicato e una VM di prova.
3. Su pbs1 configurare soltanto la management `192.168.59.20/24`: PBS non ha
   una NIC Ceph. Installare Proxmox Backup Server 4.2 e riavviare col kernel
   previsto. Inizializzare manualmente il disco da 240 GB e creare il datastore.
4. Aggiungere PBS in PVE usando `192.168.59.20`, fingerprint TLS e credenziali
   inserite interattivamente. Creare job, retention, prune e garbage collection.
5. Eseguire backup, restore come nuova VM e verifica file-level. Testare perdita
   di un PVE, non del Bosgame: backup e cluster condividono lo stesso host fisico.
