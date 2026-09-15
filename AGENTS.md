# Istruzioni per gli agenti

Repository di laboratori didattici Vagrant/VirtualBox per host Ubuntu 26.04 amd64,
Ryzen AI Max+ 395, 128 GB RAM. Documentazione e messaggi in italiano.

- Leggere README.md, docs/architecture.md e il README del laboratorio interessato.
- Ogni laboratorio è indipendente; mantenere nomi VM, MAC e reti distinti.
- Ogni lab contiene un Vagrantfile completo e provisioner locali: nessuna dipendenza da shared/.
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
