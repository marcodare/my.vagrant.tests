# Aggiornare i laboratori esistenti

Nessuno script di questa modifica ha avviato, spento o distrutto le tue VM.
I file definiscono lo stato desiderato per il prossimo utilizzo sul Bosgame.

## Proxmox Ceph / PBS

Ceph resta su 10.58.1.0/24 o 10.59.1.0/24. La differenza è PBS: non ha più la
NIC storage e PVE lo deve contattare a **192.168.59.20**, non 10.59.1.20.
Prima di togliere la NIC, in PVE aggiornare il server dello storage PBS
(mantenendo datastore, credenziali e fingerprint), poi eseguire un backup di prova.
Controllare che nessuna VM guest o migration network usi vmbr1; il segmento è
riservato ai client e alla replica Ceph.

A VM interne spente, applicare la modifica hardware tramite `vagrant reload`.
Il provisioner base riscrive i bridge: usarlo soltanto dopo aver salvato le
personalizzazioni di rete. La rete Debian scritta su disco entra in uso al
reload successivo. Non eseguire `destroy` per questa sola modifica se vuoi
conservare dati, cluster e backup.

## CloudStack da Basic a Advanced

La vecchia topologia aveva una sola rete. Ora NIC 2/cloudbr1 è fake public;
NIC 3/cloudbr0 è privata; la zona è **Advanced** con VLAN guest. Una zona Basic
popolata non viene convertita da Vagrant. Salvare ciò che serve, quindi ricreare
esplicitamente il lab oppure allestire una zona nuova con una pianificazione
separata. Per il percorso didattico è consigliato un lab vuoto.

`vagrant destroy` è una scelta distruttiva, non parte dell'aggiornamento automatico:
elimina anche NFS secondario e dischi locali. Dopo un reset voluto seguire il
nuovo README, non i precedenti IP/schema di zona.

## Nuovi lab

CloudStack HA, OpenStack e ZSvirt hanno nomi VM, MAC e reti distinti. Una sola
infrastruttura accesa alla volta. ZSvirt richiede prima la box locale; i cluster
HA e OpenStack richiedono i passi manuali dei rispettivi runbook.

## Versioni software

Le nuove installazioni richiedono CloudStack **4.23**, PVE **9.2** e PBS **4.2**.
Le box OS restano indipendenti dalle versioni dei prodotti. `lab.json` passa il
ramo richiesto ai provisioner, che selezionano i pacchetti e scrivono pin APT;
le patch del ramo sono consentite. Questo non congela ogni libreria o kernel
dipendente: non è uno snapshot dell'intero repository APT.

Su un cluster popolato, il semplice cambio del file non sostituisce la procedura
ufficiale di upgrade: backup, compatibilità, ordine dei nodi e System VM template
vanno verificati prima. Nessun upgrade è stato eseguito sulle tue VM.
