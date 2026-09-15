# Percorso manuale: CloudStack semplice

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant usare un manager Ubuntu 22.04 e tre host KVM Ubuntu 22.04
puliti, con virtualizzazione esposta sui KVM. Servono una rete public simulata,
una rete privata/VLAN e un uplink per repository; adattare IP, bridge e NIC senza
cambiare i ruoli dei traffic type. Preparare DNS diretto/inverso, NTP, accesso
SSH e un disco primary vuoto per KVM. Conservare password soltanto localmente.

1. Avviare con `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. Configurare
   hostname/NTP e bridge tramite MAC: fake public `cloudbr1` su
   `192.168.60.10/.21-.23`, private `cloudbr0` su `10.60.0.10/.21-.23`.
2. Sul manager installare MySQL 8, CloudStack Management 4.23, dnsmasq e NFS.
   Creare database con `cloudstack-setup-databases`, inizializzare il manager ed
   esportare `/srv/secondary` soltanto a `10.60.0.0/24`.
3. Sui tre host installare KVM/libvirt e `cloudstack-agent` 4.23; creare bridge
   persistenti e verificare `/dev/kvm`. Inizializzare i dischi da 120 GB come
   primary storage locale solo dopo averne verificato il device.
4. Registrare il template System VM 4.22.0 richiesto dalla documentazione 4.23.
   Dalla UI creare zona Advanced, physical network, traffic labels cloudbr0/1,
   pod `10.60.0.50-79`, public `192.168.60.100-199` e VLAN guest 100-199.
5. Aggiungere cluster/host/storage, attendere System VM e provare deploy,
   network offering e migrazione compatibile. Valori e comandi sono nel
   [README](README.md); non salvare password nel repository.
