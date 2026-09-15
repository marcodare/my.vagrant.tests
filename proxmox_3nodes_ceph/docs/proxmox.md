# Runbook Proxmox

Queste istruzioni valgono per i quattro lab PVE. Sostituire `S` con il terzo
ottetto del lab (56, 57, 58, 59). I comandi con IP di esempio non vanno copiati
senza sostituzione. Ogni README riporta gli indirizzi effettivi.

## Avvio e accesso

Dalla cartella scelta, `./scripts/up.sh` esegue:

```bash
vagrant up --provider=virtualbox  # Debian + rete + kernel PVE
vagrant reload                  # avvio del kernel PVE e dei bridge
vagrant provision               # installazione dello stack PVE
```

Il primo passaggio non ha ancora la UI Proxmox. Nessun plugin per il reboot.
Su PBS il pacchetto server è installato già al primo passaggio. La nuova rete
Debian è attiva dopo il reload. In caso di download interrotto ripetere lo step
fallito; dopo esercizi sulle reti non rilanciare il provisioner base: riscrive
il layout iniziale dei bridge.

Per ciascuno di `pve1`, `pve2`, `pve3`:

```bash
vagrant ssh pve1
sudo passwd root
uname -r                      # deve terminare in -pve
test -c /dev/kvm && echo KVM_OK
ip -br address
getent hosts pve1 pve2 pve3
chronyc tracking
sudo pveversion
```

UI: `https://192.168.S.11:8006` (anche `.12`, `.13`), utente `root`, realm
**Linux PAM**. Il certificato iniziale è autofirmato.

## Cluster: creazione e join manuale

Creare il cluster prima di creare VM sui nodi da aggiungere. Da shell root su pve1:

```bash
pvecm create study --link0 192.168.S.11
pvecm status
```

Da shell root su pve2 e pve3, rispettivamente:

```bash
pvecm add 192.168.S.11 --link0 192.168.S.12  # solo pve2
pvecm add 192.168.S.11 --link0 192.168.S.13  # solo pve3
```

Verificare fingerprint e password richiesti dal join. Controllare `pvecm nodes`
e `pvecm status`: tre nodi e quorum. In alternativa usare Datacenter → Cluster
→ Create/Join nella UI. Non forzare `expected votes` per aggirare un quorum perso.

## Prima VM e migrazione

1. In Datacenter → Storage → `local`, abilitare contenuti **Disk image** e
   **Container** oltre a ISO/template. L'installazione su Debian non crea
   `local-lvm`: usare `local`, su directory `/var/lib/vz`.
2. Caricare una ISO Linux in `local` del primo nodo e creare VM 100, 2 vCPU,
   2 GiB RAM, disco 12 GiB, NIC VirtIO su `vmbr0`. CPU uguale su tutti i nodi,
   inizialmente `host`. Verificare spazio effettivo con `df -h /var/lib/vz`.
3. Installare Linux; impostare un IP libero nello stesso segmento (es. `.101`).
   Nessun gateway finché non si aggiunge un router. Smontare la ISO dopo
   l'installazione, così non vincola la VM a un file locale del nodo sorgente.
4. Avviare un ping continuo dalla macchina host e migrare verso pve2.

Per dischi locali, da pve1:

```bash
qm migrate 100 pve2 --online --with-local-disks
```

Controllare completamento del task, ubicazione del disco e continuità del ping.
La copia del disco può impiegare tempo. Una migrazione manuale con dischi locali
non implica che il disco sia disponibile per HA dopo la perdita del nodo.

## HA e quorum

Il lab semplice permette di osservare quorum e servizi HA, ma per un test di
riavvio automatico usare una VM con tutti i dischi su Ceph nel lab dedicato.
In assenza di watchdog hardware, HA utilizza il watchdog software del guest:
questo è un esercizio di comportamento, non una garanzia di fencing fisico.

Nel lab Ceph, creare/migrare il disco della VM 100 su `ceph-vm`, quindi:

```bash
ha-manager add vm:100 --state started
ha-manager status
```

Con una sola VM sacrificabile, simulare da VirtualBox il power-off del solo nodo
che la ospita. Osservare quorum dei due superstiti, log HA e riavvio della VM.
È **restart**, con interruzione e possibile perdita dei dati non scritti; non è
live migration. Riaccendere il nodo e attendere il ripristino di Ceph prima
di altri guasti. Non spegnere due nodi contemporaneamente durante l'esercizio.

## Stop, ripresa e reset

Prima di spegnere tutto: impostare **stopped** le risorse HA dalla UI, spegnere
ordinatamente le VM/LXC e poi eseguire `vagrant halt`. Al ritorno `vagrant up`,
attendere tutti i nodi, verificare quorum/Ceph e riportare le risorse HA a started.
Evitare snapshot/ripristini indipendenti di nodi di un cluster attivo.

`vagrant destroy` è il reset completo: elimina anche VM annidate, OSD e datastore
PBS. I file in `data/` sono esterni alle VM ma non costituiscono da soli un backup.
