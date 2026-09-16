# Istruzioni per gli agenti

Repository di laboratori didattici Vagrant/VirtualBox per host Ubuntu 26.04 amd64,
Ryzen AI Max+ 395, 128 GB RAM. Documentazione e messaggi in italiano.

- Leggere README.md, docs/architecture.md, README.md e STEPS.md del laboratorio interessato.
- Ogni laboratorio è indipendente; mantenere nomi VM, MAC e reti distinti.
- Ogni lab contiene due definizioni autonome, senza dipendenze da shared/:
  - `Vagrantfile`: percorso assistito con i provisioner previsti dal laboratorio;
  - `Vagrant.start`: percorso basic che crea soltanto VM, NIC e dischi, senza
    configurare hostname, IP, pacchetti, cluster o servizi nel guest.
- Ogni README descrive scopo, topologia, risorse, reti, versioni, entrambi i
  metodi di avvio, arresto, reset e limiti del laboratorio.
- Ogni STEPS.md è la procedura didattica autorevole per partire da sistemi
  operativi puliti. Deve includere prerequisiti, rete, installazione,
  configurazione, verifiche, fault test e riferimenti; deve essere utilizzabile
  anche su VM generiche o bare metal adattando IP, NIC, dischi e gateway.
- Il percorso basic si avvia con
  `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. Usare la stessa variabile per
  tutti i comandi Vagrant e non alternare i due percorsi sulle stesse istanze.
- Preferire Python per strumenti e validazione; Ruby solo per la DSL obbligatoria di Vagrant.
- Una sola infrastruttura accesa alla volta; le altre restano spente.
- Non eseguire configure.host.sh su macOS o sulla macchina di sviluppo.
- Non avviare VM, modificare l'host, formattare dischi o distruggere risorse senza
  richiesta esplicita. La validazione statica è sempre consentita.
- Mai leggere credenziali (.env, chiavi SSH, vault), né aggiungere password al Git.
- Non committare dischi, ISO, box, dump, log o stato .vagrant.
- Non creare automaticamente cluster, pool Ceph o zone CloudStack: sono esercizi.
- Verificare fonti ufficiali prima di aggiornare versioni e repository APT.
- Eseguire ./scripts/validate.sh dopo le modifiche. Distinguere sempre verifiche
  statiche e prove reali sul Bosgame. Non dichiarare operativo un lab non avviato.
- Prima di modificare Python/TypeScript/Go leggere la relativa skill globale.
- Commit solo se richiesto; conventional commits, nessun push implicito.

## Laboratori presenti

- `proxmox_3nodes_simple`
- `proxmox_3nodes_networks`
- `proxmox_3nodes_ceph`
- `proxmox_3nodes_ceph_backup`
- `cloudstack_1manager_3nodes`
- `cloudstack_HAmanager_3nodes_linbit`
- `cloudstack_HAmanager_3nodes_ceph`
- `openstack_3nodes_simple`
- `zsvirt_1node_eval`
- `k3s_1control_3workers`
- `k8s_hacontrol_3workers`
- `linux_4nodes`
- `opnsense_4nodes_networks`
