# Infrastructure playground

Laboratori personali per studiare infrastrutture, hypervisor, reti, storage,
cluster e backup con **Vagrant + VirtualBox**. Ambiente di studio e test,
senza requisiti di produzione.

Host previsto: **Bosgame M5 AI Mini Desktop, Ryzen AI Max+ 395, 128 GB RAM,
SSD 4 TB, Ubuntu 26.04 LTS amd64**. Si esegue **una sola infrastruttura alla
volta**; tutte le altre restano spente e conservano i propri dischi.

## Laboratori

| Cartella | VM | RAM totale | Reti del lab | Obiettivo |
| --- | --- | --- | --- | --- |
| [proxmox_3nodes_simple](proxmox_3nodes_simple/README.md) | 3 PVE | 36 GiB | 1 | Cluster, VM, quorum, migrazione |
| [proxmox_3nodes_networks](proxmox_3nodes_networks/README.md) | 3 PVE | 36 GiB | 3 | Bridge, VLAN, migrazione su rete dedicata |
| [proxmox_3nodes_ceph](proxmox_3nodes_ceph/README.md) | 3 PVE | 48 GiB | 2 | Ceph, storage condiviso, HA |
| [proxmox_3nodes_ceph_backup](proxmox_3nodes_ceph_backup/README.md) | 3 PVE + PBS | 56 GiB | 2 | Backup, restore, retention |
| [cloudstack_1manager_3nodes](cloudstack_1manager_3nodes/README.md) | manager + 3 KVM | 56 GiB | 2 | Fake public/private, primary locale, NFS |
| [cloudstack_HAmanager_3nodes_linbit](cloudstack_HAmanager_3nodes_linbit/README.md) | 3 manager + 3 KVM/storage | 84 GiB | 2 | Percorso HA con LINSTOR/DRBD |
| [cloudstack_HAmanager_3nodes_ceph](cloudstack_HAmanager_3nodes_ceph/README.md) | 3 manager + 3 KVM/storage | 84 GiB | 2 | Percorso HA con RBD e NFS/CephFS |
| [openstack_3nodes_simple](openstack_3nodes_simple/README.md) | controller + 2 compute | 48 GiB | 2 | OpenStack 2025.2/Kolla, control plane semplice |
| [zsvirt_1node_eval](zsvirt_1node_eval/README.md) | 1 all-in-one | 24 GiB | 1 | Valutazione da appliance/box locale |
| [k3s_1control_3workers](k3s_1control_3workers/README.md) | 1 control + 3 worker | 32 GiB | 2 | K3s, Flannel, scheduling e fault worker |
| [k8s_hacontrol_3workers](k8s_hacontrol_3workers/README.md) | 2 LB + 3 control + 3 worker | 68 GiB | 2 | kubeadm HA, stacked etcd e Cilium |

Ogni VM ha anche una NIC NAT tecnica per Vagrant e download. I guest annidati
consumano la RAM già assegnata ai nodi. Le vCPU sono condivise con l'host.

## Primo utilizzo sul Bosgame

1. Abilitare **SVM / AMD-V** nel firmware. Ubuntu 26 è interpretato come 26.04 LTS.
2. Copiare/clonare il repository sul Bosgame.
3. Installare e configurare l'host:

   ```bash
   sudo ./configure.host.sh
   sudo reboot
   ```

4. Dopo il riavvio, con il proprio utente:

   ```bash
   ./configure.host.sh --check
   ./scripts/validate.sh
   cd proxmox_3nodes_simple
   ./scripts/up.sh
   ```

5. Seguire il README del laboratorio per credenziali, cluster ed esercizi.

Lo script host configura APT Oracle/HashiCorp con `signed-by`, installa
VirtualBox 7.2, Vagrant, driver/header e strumenti di verifica, aggiunge l'utente
a `vboxusers` e imposta `kvm.enable_virt_at_load=0` via modprobe per il prossimo
boot. Non interrompe eventuali VM KVM. Secure Boot può richiedere il completamento
della firma/MOK del driver: vedere [troubleshooting](docs/troubleshooting.md).
L'Extension Pack non è necessario. Nessun plugin Vagrant aggiuntivo richiesto.

## Operazioni quotidiane

Ogni laboratorio offre due punti di partenza:

- `Vagrantfile`: percorso assistito esistente, con provisioning dichiarato dal lab;
- `Vagrant.start`: crea solo VM, NIC e dischi; `STEPS.md` guida la configurazione manuale.

Per il percorso didattico:

```bash
VAGRANT_VAGRANTFILE=Vagrant.start vagrant up
VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh <nodo>
VAGRANT_VAGRANTFILE=Vagrant.start vagrant halt
```

La variabile deve essere presente in ogni comando. Non alternare i due file
sulle stesse VM: per cambiare percorso, salvare gli appunti e distruggere
esplicitamente l'istanza del lab con lo stesso `VAGRANT_VAGRANTFILE` usato per
crearla. `Vagrant.start` lascia senza IP le NIC del lab; la NIC NAT resta
configurata dalla box per SSH e download.

Eseguire dalla cartella del laboratorio:

```bash
vagrant status
vagrant ssh pve1                # oppure manager, kvm1, pbs1
vagrant halt                   # conserva lo stato su disco
vagrant up                     # riprende le VM già configurate
```

Prima di `halt`, spegnere le VM annidate; per i dettagli HA/Ceph vedere il
[runbook](docs/proxmox.md). Prima di passare a un altro laboratorio spegnere
quello attivo. `vagrant global-status` aiuta a controllare lo stato; il progetto
non arresta automaticamente le altre VM.

**Reset distruttivo**, solo quando si vogliono perdere tutti i dati del lab:

```bash
vagrant destroy                # chiede conferma, elimina anche dischi dei nodi
./scripts/up.sh
```

## Organizzazione

```text
AGENTS.md / CLAUDE.md       istruzioni condivise per Codex e Claude Code
.codex/                    note per il workspace Codex
.claude/commands/          comandi di revisione e validazione
configure.host.sh          preparazione dell'host Ubuntu
docs/                      architettura e runbook comuni
scripts/                   validazione statica
<laboratorio>/
  Vagrantfile / lab.json     percorso assistito, topologia e risorse
  Vagrant.start / STEPS.md   VM grezze e percorso di configurazione manuale
  scripts/up.sh            avvio iniziale
  scripts/provision/       provisioning Bash locale al laboratorio
  README.md                accesso ed esercizi specifici
  disks/ data/ logs/       spazio per file locali, esclusi da Git
```

I dischi effettivi sono gestiti da VirtualBox nella directory delle VM, non
versionati nel repository. Il disco OS è da 80 GB (200 GB per ZSvirt); i dischi aggiuntivi sono
dinamici e si popolano durante gli esercizi. Considerare anche box scaricate,
snapshot e ISO nell'uso dell'SSD.

## Cosa viene preparato

- Box Bento amd64 fissate a `202510.26.0`: Debian 13, Ubuntu 22.04/24.04.
- ZSvirt richiede una box locale preparata dall’OVA ufficiale: non viene scaricata automaticamente.
- Proxmox VE 9.2 / PBS 4.2 dai repository no-subscription, CloudStack dal ramo 4.23.
- VM, NIC, bridge, sincronizzazione oraria e pacchetti base.
- CloudStack semplice: database, manager, agent, NFS e reti fake public/private.
- CloudStack HA: sei nodi, pacchetti backend, HAProxy/Keepalived e runbook di assemblaggio;
  DB cluster, storage distribuito e zona si configurano manualmente.
- OpenStack: tre nodi e strumenti Kolla; bootstrap/precheck/deploy guidati dal README.
- Cluster, Ceph, datastore PBS e zona CloudStack vengono configurati seguendo i
  runbook: questi passaggi fanno parte dello studio.

Nei lab PVE Ceph, vmbr1 è esclusiva di Ceph; backup/PBS, guest, management e
migrazione usano vmbr0. Nei lab CloudStack, fake public è host-only e private
è una internal network con trunk VLAN guest: la zona è Advanced.

Le versioni delle box sono fissate; `versions` in lab.json fissa i rami
CloudStack 4.23, PVE 9.2 e PBS 4.2 tramite selezione pacchetti e pin APT.
Le dipendenze continuano a seguire i repository compatibili. Non è una build bit-per-bit. Vedere [architettura](docs/architecture.md)
per estendere o congelare ulteriormente i laboratori.

Ogni `Vagrantfile` è completo e modificabile direttamente; non viene generato
né caricato da una libreria condivisa. JSON e script di provisioning sono
locali al lab. Python è usato per la validazione; Ruby rimane soltanto nella
DSL richiesta da Vagrant. Per lo sviluppo degli strumenti Python, con uv:

```bash
uv run ruff check .
uv run mypy scripts tests
uv run pytest
uv run bandit -r scripts -x tests
uv run ./scripts/validate.sh
```

## Limiti e stato delle verifiche

La virtualizzazione è annidata: VirtualBox → PVE/KVM → VM di test. La presenza
di `/dev/kvm` nei nodi è un requisito; le prestazioni non rappresentano il bare
metal. Ceph e PBS risiedono sullo stesso SSD fisico: la replica e i backup
permettono esercizi, ma non proteggono dal guasto del Bosgame.

Nel lab semplice si può studiare il quorum e migrare dischi locali; **il failover
HA di una VM richiede che i suoi dischi siano disponibili sul nodo di ripartenza**.
Usare il lab Ceph per l'esercizio HA completo.

Le verifiche sono registrate in [validation.md](docs/validation.md). L'avvio end-to-end,
il comportamento nested sul Ryzen e le operazioni HA/restore devono essere
collaudati sull'host Ubuntu. Non sono dichiarati già verificati. I nuovi CloudStack HA sono percorsi di
assemblaggio e test, non cluster HA completamente installati da un singolo up.
Il failover Host HA richiede OOBM/fencing, non disponibile come BMC/IPMI nativo
in VirtualBox; live migration e HA dei servizi sono esercizi distinti.

Per ambienti già avviati leggere [aggiornamento reti](docs/network-upgrade.md)
prima di applicare i nuovi Vagrantfile.

## Fonti

Procedure e compatibilità consultate il 15 settembre 2026:

- [Oracle VirtualBox, download Linux](https://www.oracle.com/virtualization/technologies/vm/downloads/virtualbox-downloads.html).
- [HashiCorp Vagrant, installazione](https://developer.hashicorp.com/vagrant/install) e [dischi](https://developer.hashicorp.com/vagrant/docs/disks/usage).
- [Proxmox VE 9.2 su Debian 13](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie).
- [Proxmox Backup Server, installazione](https://pbs.proxmox.com/docs/installation.html).
- [CloudStack 4.23, manager](https://docs.cloudstack.apache.org/en/4.23.0.0/installguide/management-server/index.html) e [host KVM](https://docs.cloudstack.apache.org/en/4.23.0.0/installguide/hypervisor/kvm.html).
