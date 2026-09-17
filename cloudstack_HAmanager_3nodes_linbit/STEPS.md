# Percorso manuale: CloudStack HA con LINSTOR/DRBD

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant servono tre manager e tre KVM Ubuntu 22.04, due reti del lab e
un disco vuoto dedicato su ogni nodo storage. I KVM devono esporre AMD-V/VT-x.
Adattare IP, NIC e VIP mantenendo DNS, NTP e MTU uniformi. Su bare metal
collocare nodi, repliche e load balancer in failure domain distinti e
predisporre fencing/OOBM; sei VM sullo stesso host simulano soltanto la logica.

`Vagrantfile.start` crea le stesse VM, CPU, RAM, NIC, MAC e dischi del percorso
assistito, ma non configura nulla nel guest. I due file condividono `.vagrant`:
non alternarli sulle stesse istanze.

## 1. Avvio, rete e dischi

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh mgmt1
```

La NIC 1 NAT mantiene DHCP e default route. NIC 2 diventa `cloudbr1` fake
public; NIC 3 diventa `cloudbr0` privata/management/storage e trunk guest.

| Nodo | Fake public | Private | MAC NIC 2 | MAC NIC 3 |
| --- | --- | --- | --- | --- |
| `mgmt1` | `192.168.61.11` | `10.61.0.11` | `08:00:27:3d:01:02` | `08:00:27:3d:01:03` |
| `mgmt2` | `192.168.61.12` | `10.61.0.12` | `08:00:27:3d:02:02` | `08:00:27:3d:02:03` |
| `mgmt3` | `192.168.61.13` | `10.61.0.13` | `08:00:27:3d:03:02` | `08:00:27:3d:03:03` |
| `kvm1` | `192.168.61.21` | `10.61.0.21` | `08:00:27:3d:04:02` | `08:00:27:3d:04:03` |
| `kvm2` | `192.168.61.22` | `10.61.0.22` | `08:00:27:3d:05:02` | `08:00:27:3d:05:03` |
| `kvm3` | `192.168.61.23` | `10.61.0.23` | `08:00:27:3d:06:02` | `08:00:27:3d:06:03` |

Configurare hostname e bridge tramite MAC. Esempio per `mgmt1`:

```yaml
network:
  version: 2
  ethernets:
    enplabpub:
      match: {macaddress: "08:00:27:3d:01:02"}
      set-name: enplabpub
      dhcp4: false
      dhcp6: false
    enplabpriv:
      match: {macaddress: "08:00:27:3d:01:03"}
      set-name: enplabpriv
      dhcp4: false
      dhcp6: false
  bridges:
    cloudbr1:
      interfaces: [enplabpub]
      addresses: [192.168.61.11/24]
      parameters: {stp: false, forward-delay: 0}
    cloudbr0:
      interfaces: [enplabpriv]
      addresses: [10.61.0.11/24]
      parameters: {stp: false, forward-delay: 0}
```

Non aggiungere gateway o DNS ai bridge. Applicare con `netplan generate`,
`netplan try` e `netplan apply`; verificare una sola default route sulla NAT.
Inserire in `/etc/hosts` tutti i nodi sugli indirizzi `10.61.0.x`. Installare
`ca-certificates curl gnupg chrony sudo openssh-server`, abilitare Chrony e
verificare risoluzione e ping completi sulla privata.

Ogni KVM ha disco OS da 80 GB e un disco dati vuoto da 200 GB. Identificarlo
con `lsblk` e `/dev/disk/by-id`; non inizializzarlo ancora.

## 2. Control plane CloudStack

Sui tre manager installare dal solo ramo 4.23 CloudStack Management, MySQL 8,
MySQL Router, HAProxy, Keepalived, dnsmasq, netfilter-persistent e client NFS.
`scripts/provision/ha-manager.sh` è il riferimento del percorso assistito per
repository, pin, configurazione MySQL, VIP e NAT. Nel percorso manuale eseguire
e verificare i passaggi singolarmente.

Riservare su entrambe le reti `.4` per gateway/DNS e `.5` per UI/API; sulla
privata riservare inoltre `.6` per il controller LINSTOR e `.7` per NFS.
Keepalived usa VRRP unicast fra `10.61.0.11-.13`; HAProxy bilancia i manager
sulla porta 8080 e pubblica la UI sulla VIP porta 80.

Seguire integralmente [docs/control-plane.md](docs/control-plane.md): creare lo
schema una sola volta, validare la compatibilità con Group Replication, creare
InnoDB Cluster single-primary, bootstrap dei router locali e configurare i tre
manager con le stesse chiavi. Non avviare tre database CloudStack indipendenti.
Una risposta 503 prima dell'avvio dei backend manager è prevista.

## 3. KVM e LINSTOR

Su ciascun KVM verificare `/dev/kvm`, poi installare libvirt, CloudStack Agent
4.23 e i client NFS. Impostare in `agent.properties` `cloudbr0` per private e
guest, `cloudbr1` per public e `host-passthrough` per la CPU. Verificare agent,
libvirt e accesso SSH dal manager prima di registrare gli host.

Installare DRBD 9, LINSTOR controller/satellite/client, Reactor, LVM e i
componenti NFS. Se il modulo DRBD non corrisponde al kernel, riavviare il singolo
nodo e ricontrollare prima di proseguire. Non formattare il disco da 200 GB come
storage locale CloudStack.

Seguire integralmente [docs/storage.md](docs/storage.md): creare i tre thin
pool, satellite e resource group; spostare il database controller su una
risorsa DRBD con quorum; attivare un solo controller tramite Reactor e VIP
`10.61.0.6`; creare NFS HA sulla VIP `10.61.0.7`. Non promuovere risorse in
assenza di quorum e non avviare controller o NFS indipendenti su tutti i nodi.

## 4. Zona e criteri di accettazione

Importare il System VM template verificato sul secondario NFS. Creare la zona
Advanced con public `cloudbr1`, management/storage/guest `cloudbr0`, system IP
`10.61.0.50-79`, public pool `192.168.61.100-199` e VLAN guest 100-199.
Impostare `use.local.storage=false` e `system.vm.use.local.storage=false`.

Prima dei fault test richiedere DB e storage in quorum, repliche UpToDate,
manager raggiungibili, tre host `Up`, System VM `Running` e una VM su storage
condiviso. Provare un solo guasto alla volta secondo la matrice del runbook:
manager, primary DB, proprietario VIP, controller LINSTOR, NFS e singolo KVM.
Verificare I/O durante live migration. Host HA resta escluso senza fencing
reale: non usare un falso fencing che dichiari successo.

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt mgmt1
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up mgmt1
```

## 5. Arresto, ripresa e reset

Spegnere workload e System VM, verificare le repliche, poi fermare ordinatamente
manager, DB e storage secondo i runbook. Dopo uno stop totale ripristinare prima
storage e quorum DB, poi router e manager.

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```

`destroy` elimina database, risorse DRBD e VM annidate. Per cambiare percorso
distruggere prima con la definizione usata per creare le istanze.

Fonti e comandi di dettaglio sono raccolti in
[control-plane.md](docs/control-plane.md) e [storage.md](docs/storage.md).
