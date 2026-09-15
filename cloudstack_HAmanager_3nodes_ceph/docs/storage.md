# Ceph RBD e secondario NFS su CephFS

Tre KVM/storage: kvm1/2/3, IP **10.62.0.21/.22/.23**. Un disco dati raw
200 GB per nodo. Tutto il traffico storage usa la rete privata cloudbr0.
Pacchetti cephadm/Squid già installati; cluster/OSD non vengono creati da Vagrant.

## 1. Bootstrap e accesso fra nodi

Da root su kvm1, solo la prima volta:

```bash
cephadm bootstrap --mon-ip 10.62.0.21 --cluster-network 10.62.0.0/24 --ssh-user vagrant
ceph config set global public_network 10.62.0.0/24
ceph cephadm get-pub-key > /tmp/cephadm.pub
```

Installare questa **chiave pubblica** nell'authorized_keys dell'utente vagrant
su tutti e tre i KVM (anche kvm1); quell'utente deve avere sudo senza password.
Non copiare chiavi private. Seguire il flusso cephadm ufficiale se si preferisce
un altro utente SSH. Poi:

```bash
ceph orch host add kvm2 10.62.0.22
ceph orch host add kvm3 10.62.0.23
ceph orch apply mon --placement="3 kvm1 kvm2 kvm3"
ceph orch apply mgr --placement="2 kvm1 kvm2"
ceph orch host ls
ceph orch device ls
```

## 2. OSD e pool

Su ogni nodo controllare `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,SERIAL`.
Scegliere esclusivamente il disco **200 GB** non usato. La creazione OSD
sovrascrive il disco selezionato; non usare `--all-available-devices`.
Esempio da adattare per ciascun nodo:

```bash
ceph orch daemon add osd kvm1:/dev/disk/by-id/ID_DATI_VERIFICATO
# Ripetere per kvm2 e kvm3 con l'ID corretto.
ceph osd pool create cloudstack
ceph osd pool set cloudstack size 3
ceph osd pool set cloudstack min_size 2
ceph osd pool set cloudstack pg_autoscale_mode on
rbd pool init cloudstack
ceph -s
ceph osd tree
```

Attendere tre OSD Up/In e PG active+clean. La regola CRUSH deve separare le
copie per **host**. Tre dischi da 200 GB con replica 3 danno meno di 200 GB
utilizzabili complessivi, condivisi anche con il secondario CephFS.

Creare client `cloudstack` con permessi RBD sul solo pool; custodire la chiave
nel guest e inserirla nella UI senza stamparla nei log/repository. In Add Primary
Storage scegliere **RBD**, monitor private, porta 6789 se richiesta dal driver,
pool `cloudstack`, utente `cloudstack` e chiave CephX. Tutti i KVM devono poter
raggiungere tutti i MON: verificare che la configurazione effettiva includa
la mon_host list .21/.22/.23 e non rimanga dipendente da un unico indirizzo.
Vedere [integrazione Ceph/CloudStack](https://docs.ceph.com/en/squid/rbd/rbd-cloudstack/).

## 3. Secondario realmente ridondato

NFS su un solo manager vanificherebbe parte dell'esercizio HA. Qui si usa CephFS
replicato, almeno due MDS e due NFS-Ganesha, con ingress/VIP **10.62.0.7**:

```bash
ceph fs volume create secondary
ceph orch apply mds secondary --placement="2 kvm1 kvm2"
ceph nfs cluster create secondary "2 kvm1 kvm2" --ingress --virtual_ip 10.62.0.7/24 --port 12049
ceph nfs export create cephfs --cluster-id secondary --pseudo-path /secondary --fsname secondary --squash no_root_squash
ceph nfs cluster info secondary
ceph orch ls
```

Verificare anche replica 3/min_size 2 e failure domain host dei pool CephFS.
La porta backend 12049 evita conflitti con il frontend NFS 2049. Controllare
che ingress sia su almeno due nodi e che i daemon siano healthy. Il passaggio
NFS-Ganesha/CloudStack è una parte sperimentale da validare esplicitamente:
non considerare HA collaudata solo perché il VIP risponde.

Sul manager montare per il solo import template:

```bash
sudo mkdir -p /mnt/secondary
sudo mount -t nfs -o vers=4.1 10.62.0.7:/secondary /mnt/secondary
```

Impostare **secstorage.nfs.version=4.1** nella zona prima di creare le System VM.
Usare il template KVM indicato dalla guida della release CloudStack installata e il comando
`cloud-install-sys-tmplt -m /mnt/secondary -u URL_VERIFICATO -h kvm`.
Aggiungere secondary NFS server `10.62.0.7`, path `/secondary` nella UI.
Verificare mount su host e SSVM, lettura/scrittura e recovery dopo perdita
NFS-Ganesha: il protocollo v4 mantiene stato e richiede corretta recovery.

Solo dopo questi controlli: offering shared + VM su RBD, live migration fra
KVM, e prove della [matrice HA](control-plane.md). Non abilitare local storage.

Fonti: [cephadm](https://docs.ceph.com/en/squid/cephadm/install/),
[NFS Ceph](https://docs.ceph.com/en/squid/mgr/nfs/),
[CloudStack storage](https://docs.cloudstack.apache.org/en/4.23.0.0/adminguide/storage.html).

### Template System VM per CloudStack 4.23

La [guida 4.23](https://docs.cloudstack.apache.org/en/4.23.0.0/installguide/management-server/index.html#prepare-the-system-vm-template)
indica attualmente **systemvmtemplate-4.22.0-x86_64-kvm.qcow2.bz2**, pubblicato
in https://download.cloudstack.org/systemvm/4.22/. Non inventare un URL 4.23:
la versione del template non coincide necessariamente con quella del manager.
Verificare checksum e note della release prima dell'import.
