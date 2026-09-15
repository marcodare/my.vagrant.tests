# Percorso manuale: valutazione ZSvirt

## Uso su Vagrant, VM generiche o bare metal

Su VM generica importare l'immagine supportata ed esporre la virtualizzazione;
su bare metal seguire il metodo di installazione ZSvirt previsto dal vendor.
Gli indirizzi del lab sono esempi: adattare management, gateway, DNS, NTP e NIC
conservando accesso console. Verificare prima supporto hardware, firmware,
controller disco e HCL; la procedura OVA descritta qui riguarda il test annidato.

1. Scaricare l'OVA ufficiale e verificarne checksum/licenza. Importarla in
   VirtualBox, creare l'utente `vagrant` con sudo e chiave Vagrant, abilitare
   SSH/DHCP sulla prima NIC e impacchettarla come `local/zsvirt-h84r` versione 0.
2. Esportare la password solo nella shell e avviare:
   `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`.
3. Dalla console identificare NIC 2 tramite MAC e assegnare
   `192.168.63.139/25`; la NIC NAT conserva route e accesso SSH. Verificare che
   la rete host-only appartenga alla metà alta di `.63/24`.
4. Usare `zstack-ctl change_ip`, avviare i servizi e aprire la UI HTTPS. Non
   inizializzare automaticamente management/storage: annotare ogni scelta.
5. Verificare compatibilità nested KVM, inventario disco da 100 GB e funzioni
   base. Il [README](README.md) descrive preparazione box e limiti: VirtualBox
   non è indicato come piattaforma certificata, quindi il risultato è esplorativo.
