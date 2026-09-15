# Percorso manuale: CloudStack HA con Ceph

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant servono tre manager e tre KVM Ubuntu 22.04, rete public, rete
privata e un disco OSD vuoto per KVM. Adattare indirizzi, NIC e VIP mantenendo
DNS/NTP/MTU coerenti e virtualizzazione hardware sui KVM. In un ambiente reale
separare i failure domain Ceph, i load balancer e l'alimentazione; predisporre
fencing/OOBM prima di interpretare un riavvio automatico come HA sicura.

1. Avviare `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`; configurare fake
   public `192.168.62.0/24`, private `10.62.0.0/24` e bridge cloudbr1/0.
2. Costruire i tre manager CloudStack 4.23, MySQL, HAProxy e Keepalived seguendo
   [docs/control-plane.md](docs/control-plane.md). Validare Group Replication
   sullo schema reale prima di considerare ridondato il database.
3. Sui tre KVM installare libvirt/agent e Ceph Squid. Usare i dischi raw da
   200 GB per 3 OSD, 3 MON e almeno 2 MGR; public e cluster network restano sulla
   privata. Creare pool RBD size 3/min_size 2 come da [docs/storage.md](docs/storage.md).
4. Creare CephFS e NFS-Ganesha ridondato per secondary storage, verificando
   mount NFS 4.1 e failover prima di inserirlo in CloudStack.
5. Creare zona Advanced, registrare System VM, poi provare live migration e
   fault singoli. Il Bosgame e il suo SSD restano punti di guasto comuni.
