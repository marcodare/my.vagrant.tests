# Percorso manuale: Proxmox e reti

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant preparare tre Debian 13 amd64 puliti con AMD-V/Intel VT
disponibile e tre NIC per nodo: management, migrazione e guest/VLAN. Gli IP del
lab sono esempi sostituibili; mantenere reti separate, hostname/DNS coerenti,
NTP e accesso console durante i cambi di rete. La NIC NAT citata sotto equivale
all'uplink di servizio scelto nell'ambiente reale.

1. Avviare con `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. Configurare
   hostname, `/etc/hosts`, NTP e Proxmox VE 9.2 come descritto nel percorso
   base di [docs/proxmox.md](docs/proxmox.md).
2. Associare le NIC tramite MAC, senza dipendere dal nome assegnato dal kernel.
   Creare `vmbr0` su `192.168.57.11-.13/24`, `vmbr1` su
   `10.57.1.11-.13/24` per migrazione e `vmbr2` su `10.57.2.11-.13/24` per
   guest/VLAN. Non impostare gateway su questi bridge; la NAT resta tecnica.
3. Rendere `vmbr2` VLAN-aware, creare VLAN e VM di prova, quindi verificare
   isolamento, tagging e MTU con ping e cattura pacchetti.
4. Creare il cluster PVE su vmbr0. Nelle Datacenter Options selezionare la rete
   `10.57.1.0/24` come migration network, poi misurare che la migrazione usi
   vmbr1. Simulare perdita di una NIC/rete e osservare gli effetti.

Prima di usare il Vagrantfile automatico eliminare esplicitamente le VM create
con `Vagrant.start`; i due percorsi non condividono una configurazione guest.
