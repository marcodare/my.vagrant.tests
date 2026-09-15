# Percorso manuale: Proxmox semplice

## Uso su Vagrant, VM generiche o bare metal

`Vagrant.start` è solo il punto di partenza VirtualBox. Fuori da Vagrant usare
tre sistemi Debian 13 amd64 puliti con virtualizzazione hardware esposta, almeno
le risorse del README e una NIC di management comune. Sostituire IP e nomi NIC
nei passi seguenti, mantenere DNS/hostname coerenti, NTP attivo e una route per
i repository. Prima di modificare kernel o rete conservare accesso console.

1. Avviare `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up` e accedere con
   `vagrant ssh pve1`. Identificare NIC e MAC con `ip -br link`.
2. Su ogni nodo impostare hostname, `/etc/hosts`, NTP e un bridge `vmbr0` sulla
   NIC host-only: `192.168.56.11/24`, `.12`, `.13`; nessun gateway su vmbr0.
   Conservare la default route della NIC NAT e verificare ping e risoluzione.
3. Aggiungere chiave e repository Proxmox VE 9.2 no-subscription per Debian 13,
   installare il kernel PVE e riavviare. Verificare `uname -r`, poi installare
   `proxmox-ve`, rimuovere il kernel Debian solo dopo il boot corretto e
   controllare `pveversion -v`.
4. Impostare una password root locale, aprire `https://192.168.56.11:8006` e
   creare il cluster su pve1. Unire pve2 e pve3 usando vmbr0.
5. Creare VM di prova con storage locale, testare migrazione e quorum. Lo storage
   locale non permette riavvio HA su un altro nodo. Eseguire gli esercizi e le
   verifiche dettagliate in [docs/proxmox.md](docs/proxmox.md).

Non alternare questo file con il `Vagrantfile` automatico sulla stessa istanza:
prima occorre distruggere esplicitamente il lab, perdendo i suoi dati.
