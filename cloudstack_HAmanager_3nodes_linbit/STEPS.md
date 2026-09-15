# Percorso manuale: CloudStack HA con LINSTOR/DRBD

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant servono tre manager e tre KVM Ubuntu 22.04, due reti del lab e
un disco vuoto dedicato su ogni nodo storage. I KVM devono esporre VT-x/AMD-V.
Adattare IP/NIC/VIP mantenendo DNS, NTP e MTU uniformi. Per una prova realistica
collocare nodi, repliche e load balancer in failure domain distinti e predisporre
fencing/OOBM; su sei VM dello stesso host si studia solo la logica del failover.

1. Avviare `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up` e configurare le NIC:
   fake public `192.168.61.0/24`, private `10.61.0.0/24`, bridge cloudbr1/0.
2. Preparare sui tre manager MySQL 8, CloudStack 4.23, HAProxy e Keepalived.
   Costruire e validare il control plane seguendo [docs/control-plane.md](docs/control-plane.md),
   fermandosi se lo schema 4.23 risulta incompatibile con Group Replication.
3. Sui KVM installare libvirt/agent e lo stack DRBD 9 + LINSTOR. Identificare i
   dischi raw da 200 GB, creare LVM thin, satellite, controller DB replicato,
   resource group e VIP seguendo [docs/storage.md](docs/storage.md).
4. Preparare secondary NFS tramite LINSTOR Gateway, poi creare zona Advanced,
   cluster, storage offering shared e template System VM.
5. Collaudare replica, live migration, perdita controller/LB/storage e ripresa.
   Host HA CloudStack richiede fencing/OOBM reale, che VirtualBox non fornisce.
