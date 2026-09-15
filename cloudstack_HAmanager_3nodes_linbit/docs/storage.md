# LINSTOR + DRBD 9 e secondario NFS HA

Tre KVM/storage **kvm1/2/3**, IP **10.61.0.21/.22/.23**, un disco raw 200 GB
ciascuno. Pacchetti LINBIT community/PPA, satellite e DRBD 9 sono preparati da
Vagrant; controller, storage pool e risorse non vengono inizializzati automaticamente.

## 1. Pool fisico sui tre nodi

Verificare `modinfo -F version drbd` (9.x), DKMS e `/dev/kvm`. Con kernel/module
mismatch riavviare il nodo prima di procedere. Su ogni KVM identificare con
`lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,SERIAL` il disco **200 GB** vuoto.
I comandi seguenti sono distruttivi sul dispositivo scelto: sostituire l'ID,
non ripetere su un lab popolato e non scegliere mai il disco OS.

```bash
pvcreate /dev/disk/by-id/ID_DATI_VERIFICATO
vgcreate vg_linstor /dev/disk/by-id/ID_DATI_VERIFICATO
lvcreate -l 80%FREE --thinpool thinpool vg_linstor
```

## 2. Primo controller e risorse VM

Avviare inizialmente il controller **solo su kvm1** con
`systemctl start linstor-controller`. Da kvm1:

```bash
linstor node create kvm1 10.61.0.21
linstor node create kvm2 10.61.0.22
linstor node create kvm3 10.61.0.23
linstor storage-pool create lvmthin kvm1 pool vg_linstor/thinpool
linstor storage-pool create lvmthin kvm2 pool vg_linstor/thinpool
linstor storage-pool create lvmthin kvm3 pool vg_linstor/thinpool
linstor resource-group create cloudstack --place-count 3 --storage-pool pool
linstor volume-group create cloudstack
linstor node list
linstor storage-pool list
```

I nomi dei nodi LINSTOR devono coincidere con quelli degli host CloudStack.
Usare IP privati per la replica; non creare interfacce LINSTOR sulla fake public.
Il pool thin richiede monitoraggio di data e metadata: non confondere capacità
virtuale sovra-allocata con spazio fisicamente disponibile.

## 3. Controller HA: evitare tre database indipendenti

Seguire il capitolo **Highly Available LINSTOR Controller** della
[guida LINBIT](https://linbit.com/drbd-user-guide/linstor-guide-1_0-en/#s-linstor_ha):

1. Creare una risorsa DRBD `linstor_db` replicata su tutti e tre i KVM.
2. Fermare il controller e trasferire il suo database su quel filesystem.
3. Predisporre su tutti i nodi `var-lib-linstor.mount` per `/var/lib/linstor`.
4. Configurare DRBD Reactor affinché il filesystem e il controller siano attivi
   **solo sul Primary**. Usare majority quorum e politica di sospensione I/O
   quando non è disponibile il quorum; non forzare una promozione in split brain.
5. Inserire la VIP **10.61.0.6/24** nella sequenza del promoter; template locale
   in `../config/linstor_db.toml.example`. Il file da solo non crea il database
   DRBD o il mount unit: installarlo solo dopo i passaggi precedenti.
6. Disabilitare l'avvio indipendente di linstor-controller, abilitare Reactor,
   quindi verificare il failover e impostare sui client l'endpoint VIP .6.

Al completamento, `touch /var/lib/infra-lab/storage-ready` su tutti i KVM.
Nella UI CloudStack: primary protocol **Linstor**, server
**http://10.61.0.6:3370**, resource group **cloudstack**. La VIP è necessaria:
usare l'IP fisso kvm1 lascerebbe l'API storage come punto singolo di guasto.

## 4. Secondario NFS HA

Installare **LINSTOR Gateway** compatibile sui nodi di storage seguendo
[la guida ufficiale](https://linbit.com/drbd-user-guide/linstor-guide-1_0-en/#ch-linstor-gateway).
Il PPA community può non offrire tutte le release/tool: controllare
`apt-cache policy linstor-gateway`; se assente usare il pacchetto/release upstream
verificato, senza assumere che un repository con subscription sia accessibile.
Non viene scaricato né installato un binario non verificato dal provisioning.

Dopo avere installato Gateway e predisposto Reactor sui tre KVM:

```bash
linstor resource-group create secondary --place-count 3 --storage-pool pool
linstor volume-group create secondary
linstor-gateway check-health
linstor-gateway nfs create secondary 10.61.0.7/24 40G --resource-group secondary --allowed-ips 10.61.0.0/24
linstor-gateway nfs list
```

Verificare il comando con `linstor-gateway nfs create --help` della versione
installata. L'export e il filesystem sono gestiti da Gateway/Reactor: non avviare
un nfs-server indipendente su tutti i nodi. Usare il percorso export riportato
in `nfs list` (non assumerlo), montarlo dal manager e importare il System VM
template KVM corrispondente alla release CloudStack installata.

In CloudStack aggiungere secondary NFS con server **10.61.0.7** e il percorso
verificato. Osservare I/O e mount dopo perdita del nodo proprietario del VIP.
Dedicare 40 GB al secondario lascia spazio alle VM e al database controller,
ma le tre copie consumano capacità su tutti e tre i dischi.

## 5. Prove

Prima ottenere tutte le repliche UpToDate, poi creare una VM su offering shared,
eseguire live migration con ping e scritture in corso e testare il failover del
controller e di NFS. Per guasti di host e partizioni serve la procedura di
fencing descritta nella [matrice HA](control-plane.md), non basta DRBD replicato.

Fonti: [CloudStack LINSTOR](https://docs.cloudstack.apache.org/en/4.23.0.0/adminguide/storage.html),
[VIP controller](https://kb.linbit.com/linstor/linstor-ha-controller-vip-configuration/),
[architettura HCI LINBIT](https://hci.linbit.com/linbit-cloudstack-hci-appliance/).

### Template System VM per CloudStack 4.23

La [guida 4.23](https://docs.cloudstack.apache.org/en/4.23.0.0/installguide/management-server/index.html#prepare-the-system-vm-template)
indica attualmente **systemvmtemplate-4.22.0-x86_64-kvm.qcow2.bz2**, pubblicato
in https://download.cloudstack.org/systemvm/4.22/. Non inventare un URL 4.23:
la versione del template non coincide necessariamente con quella del manager.
Verificare checksum e note della release prima dell'import.
