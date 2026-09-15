# Diagnostica e collaudo sul Bosgame

## Host

- **Driver VirtualBox:** `sudo modprobe vboxdrv`, `dkms status`,
  `journalctl -k -b`, `mokutil --sb-state`. Con Secure Boot seguire la procedura
  Ubuntu di firma/enrollment MOK proposta durante l'installazione del modulo,
  poi riavviare e verificare `/dev/vboxdrv`. Lo script non disabilita Secure Boot.
- **AMD-V occupato:** riavviare dopo configure.host.sh; la configurazione
  `options kvm enable_virt_at_load=0` evita l'acquisizione anticipata. Non
  scaricare KVM mentre altre VM lo usano. Il parametro riguarda KVM sull'host,
  non quello dentro i guest.
- **Repository assente:** lo script si ferma se il repository `resolute` non è
  disponibile. Non sostituirlo con `noble` o altre release senza verifica.
- **VirtualBox/Vagrant incompatibili:** controllare le versioni installate e
  il supporto del provider. Le box di questo progetto sono amd64.
- **Rete host-only rifiutata:** un `vagrant up` che fallisce creando
  l'interfaccia, di solito sui lab k3s/k8s, significa che il range non è
  autorizzato in `/etc/vbox/networks.conf`. Senza quel file VirtualBox accetta
  solo `192.168.56.0/21`, cioè fino a `192.168.63.255`. Verificare con
  `./configure.host.sh --check` e, se serve, rieseguire `sudo ./configure.host.sh`:
  aggiunge i due range del progetto senza togliere quelli di altri laboratori.
- **APT: "valori in conflitto per l'opzione Signed-By":** l'host ha già lo stesso
  repository (tipicamente HashiCorp) configurato da un'altra procedura con il
  keyring in un percorso diverso. Lo script ora rileva la sorgente esistente e
  non ne aggiunge una seconda; se l'errore resta da un tentativo precedente,
  rimuovere il file `infra-*.list` in eccesso e rilanciare lo script, che in
  apertura ripulisce comunque le proprie sorgenti.
- **Reti host-only:** controllare `VBoxManage list hostonlyifs` e
  `VBoxManage list dhcpservers`. Eventuali DHCP su una rete del lab possono
  interferire con IP statici e DHCP CloudStack: disabilitare solo quello della
  rete interessata tramite VirtualBox → Tools → Network. Non modificare DHCP LAN.

## Guest

- **PVE senza UI:** completare `vagrant reload` e `vagrant provision` dopo
  l'installazione del kernel. `uname -r` deve terminare in `-pve`.
- **Nested assente:** `grep -w svm /proc/cpuinfo`, `sudo modprobe kvm_amd`,
  `ls -l /dev/kvm`. Verificare SVM firmware e nested virtualization in VirtualBox.
  Non usare emulazione software come prova di prestazioni.
- **Rete dopo reload:** `ip -br a`, `ip route`, `bridge link`,
  `journalctl -u networking -b` (Debian) o `networkctl` (Ubuntu).
  La default route deve restare sulla NIC NAT, non sulla rete Corosync.
- **Disco OS piccolo:** il VDI può essere 80 GB ma il filesystem della box
  più piccolo. Usare `lsblk -f`, `findmnt /`, `df -h`; adattare partizione e
  filesystem al layout realmente rilevato prima di caricare grandi ISO/backup.
- **Join fallito:** hostname univoci, risoluzione su IP management, orologi
  sincronizzati, nodi senza VM e raggiungibilità bidirezionale. Correggere la
  causa, non forzare quorum o copiare a mano `/etc/pve`.
- **CloudStack:** `systemctl status cloudstack-management` sul manager,
  `systemctl status cloudstack-agent libvirtd` sui KVM. Log in
  `/var/log/cloudstack/`; possono contenere dati sensibili, non committarli.

## Checklist di accettazione reale

1. `./configure.host.sh --check` e `./scripts/validate.sh` superati.
2. Un solo laboratorio attivo, bridge/IP corretti dopo riavvio.
3. `/dev/kvm` presente su ogni hypervisor e prima VM annidata avviata.
4. PVE: tre nodi con quorum; migrazione completata e disco presente sul target.
5. Networks: ping stesso VLAN tag riuscito, tag differenti isolati.
6. Ceph: tre OSD, PG active+clean; un nodo perso e recovery completata.
7. PBS: backup verificato e restore avviabile con VMID differente.
8. CloudStack: tre host Up, System VM Running, istanza su storage locale,
   template/ISO disponibili sul secondario NFS.

Annotare versioni, esito e tempi in un documento del lab. I controlli statici
non sostituiscono questa checklist.
