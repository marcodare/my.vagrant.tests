# Percorso manuale: Proxmox VE semplice

Con Vagrant questa procedura parte da tre cloni non configurati della box
`local/proxmox-ve-9.2`: PVE 9.2 e il kernel sono già installati, mentre identità,
rete e cluster restano esercizi manuali. `Vagrantfile.start` usa le stesse box,
VM, risorse, NIC, MAC e dischi del percorso assistito, ma non dichiara alcun
provisioner del guest.

Su VM generiche o bare metal si può invece partire da Debian 13 pulita: in quel
caso seguire anche le sezioni 6, 7 e 9 dedicate all'installazione di PVE.

Lo scopo è capire l'ordine delle dipendenze: prima identità PVE e rete, poi
verifiche del kernel e dello storage, infine cluster, quorum e VM annidate. Creare automaticamente
il cluster toglierebbe proprio la parte più importante dell'esercizio.

## Risultato atteso

| Nodo | IP management | MAC NIC management | vCPU | RAM |
| --- | --- | --- | --- | --- |
| `pve1` | `192.168.56.11/24` | `08:00:27:38:01:02` | 6 | 12 GiB |
| `pve2` | `192.168.56.12/24` | `08:00:27:38:02:02` | 6 | 12 GiB |
| `pve3` | `192.168.56.13/24` | `08:00:27:38:03:02` | 6 | 12 GiB |

Ogni nodo avrà:

- NIC 1 NAT/DHCP per `vagrant ssh`, APT, DNS e NTP;
- NIC 2 host-only collegata a `vmbr0`, senza gateway;
- hostname e risoluzione locale coerenti;
- kernel PVE con `/dev/kvm` disponibile tramite virtualizzazione annidata;
- Proxmox VE 9.2 proveniente dalla box locale oppure installato da Debian;
- appartenenza al cluster `study`, creato solo dopo la verifica dei singoli nodi.

Management, Corosync, migrazione e traffico delle VM condividono `vmbr0`. È una
semplificazione didattica: in produzione Corosync e storage richiedono una
progettazione più rigorosa e, quando possibile, reti dedicate.

## Prerequisiti e cautele

- Preparare il Bosgame con `configure.host.sh` e tenere spenti gli altri lab.
- Verificare che AMD-V/SVM sia attivo nel firmware e disponibile a VirtualBox.
- Conservare accesso console prima di cambiare rete o kernel, soprattutto su VM
  generiche o bare metal.
- Non eseguire questi comandi sull'host Ubuntu: sono destinati ai tre guest.
- Non creare VM su `pve2` o `pve3` prima del join: l'ingresso nel cluster
  sostituisce la configurazione locale in `/etc/pve`.
- Non usare `pvecm expected` per mascherare una perdita di quorum.

Fuori da Vagrant servono tre installazioni PVE 9.2 standalone oppure tre Debian
13 amd64 pulite da convertire con le sezioni dedicate, con virtualizzazione
hardware esposta, almeno le risorse indicate sopra, una NIC comune per il
management e una route verso i repository. Su bare metal adattare IP, MAC,
nomi NIC e gateway, mantenendo invariati i principi della procedura.

## 1. Creare i tre cloni PVE non configurati

Dalla cartella `proxmox_3nodes_simple`:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
```

Usare la stessa variabile per **ogni** comando Vagrant del percorso manuale.
I due file condividono la directory `.vagrant`: senza la variabile viene
caricato il `Vagrantfile` assistito, che può operare sulle stesse macchine e
avviare i provisioner.

Per lavorare un nodo alla volta:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Ripetere poi i passaggi su `pve2` e `pve3`, sostituendo nome, IP e MAC secondo
la tabella.

## 2. Rilevare lo stato iniziale

Prima di apportare modifiche, su ogni nodo eseguire:

```bash
cat /etc/os-release
hostnamectl
ip -br link
ip -br address
ip route
cat /etc/resolv.conf
lscpu | grep -E 'Architecture|Virtualization'
lsblk
df -hT
```

Con `Vagrantfile.start`, verificare inoltre:

```bash
pveversion
uname -r
hostname -s
sudo test ! -e /etc/pve/corosync.conf
```

PVE deve essere nel ramo 9.2, il kernel deve terminare in `-pve`, l'hostname
iniziale deve essere `proxmox-template` e il nodo non deve appartenere a un
cluster. L'installer ISO ha creato un primo `vmbr0` con IP statico
(`10.0.2.15/24`, gateway `10.0.2.2`) che ha come unica porta la NIC NAT: la
default route esce quindi dal bridge, non dalla NIC. Questo `vmbr0` verrà
riassegnato alla rete management nel passo 5. La seconda NIC dovrebbe essere
presente ma senza IPv4 perché nel file Vagrant è impostato `auto_config: false`.

Individuare le interfacce tramite MAC e la porta del bridge iniziale:

```bash
ip -o link
ip route show default
bridge link
```

Non assumere nomi come `enp0s3` o `enp0s8`: possono cambiare fra box e hardware.
Annotare:

- la NIC NAT, cioè la porta di `vmbr0` mostrata da `bridge link`
  (su un'installazione generica è invece la NIC di `ip route show default`);
- la NIC management, identificata dal MAC della tabella;
- il gateway e il DNS attuali (`ip route show default`, `/etc/resolv.conf`).

Il disco virtuale è impostato a 80 GB, ma `lsblk` e `df` possono mostrare un
filesystem più piccolo. L'aumento del supporto VDI non implica automaticamente
l'espansione della partizione o del filesystem.

## 3. Finalizzare manualmente l'identità PVE

Ogni clone contiene ancora il database `pmxcfs`, la CA e i certificati del
template. Cambiare soltanto `/etc/hostname` produrrebbe tre nodi incoerenti.
Prima di creare cluster o VM, operare su **un nodo alla volta**.

In `/etc/hosts` rimuovere le righe riferite a `proxmox-template`, quindi
aggiungere su tutti i nodi:

```text
# BEGIN INFRA LAB
192.168.56.11 pve1.lab.test pve1
192.168.56.12 pve2.lab.test pve2
192.168.56.13 pve3.lab.test pve3
# END INFRA LAB
```

Proxmox usa intensamente hostname e risoluzione dei nomi. Il nome del nodo deve
risolversi nell'IP management stabile, non nel loopback né nell'indirizzo DHCP
della NAT.

Solo sui cloni della box locale, verificare prima che non esistano cluster o
guest e rigenerare l'identità. L'esempio è per `pve1`; sostituire `NODE` sugli
altri due nodi:

```bash
NODE=pve1
sudo test ! -e /etc/pve/corosync.conf
sudo find /etc/pve/nodes -type f \
  \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -print
# L'ultimo comando non deve stampare nulla.

sudo systemctl stop pve-ha-lrm pve-ha-crm pvescheduler \
  pvestatd pveproxy pvedaemon
sudo systemctl stop pve-cluster
if mountpoint -q /etc/pve; then echo '/etc/pve ancora montato'; exit 1; fi
sudo rm -f /var/lib/pve-cluster/config.db /var/lib/pve-cluster/config.db-*
sudo hostnamectl set-hostname "$NODE"
sudo systemctl start pve-cluster
sudo pvecm updatecerts --force
sudo systemctl start pvedaemon pveproxy pvestatd pvescheduler \
  pve-ha-crm pve-ha-lrm
```

La cancellazione di `config.db` è ammessa qui soltanto perché il clone è
standalone e privo di guest. Non eseguirla mai su un nodo configurato. Su una
Debian pulita, che non possiede ancora `pmxcfs`, impostare soltanto l'hostname
con `hostnamectl` e continuare con l'installazione.

### Watchdog software nelle VM VirtualBox

`watchdog-mux` di Proxmox arma il modulo `softdog` con timeout di 10 secondi e
lo usa per il fencing HA. Un guest VirtualBox annidato può restare congelato
più a lungo (import della box, recupero del clock, pause o carico del host):
in quel caso il kernel del guest si resetta da solo a metà lavoro, lasciando
file troncati come un `/etc/hosts` vuoto. Sui cloni VirtualBox, con i servizi
HA fermi, rendere il watchdog solo diagnostico:

```bash
echo 'options softdog soft_noboot=1' | sudo tee /etc/modprobe.d/infra-lab-softdog.conf
sudo systemctl stop pve-ha-lrm pve-ha-crm
sudo systemctl stop watchdog-mux
sudo modprobe -r softdog
sudo systemctl start watchdog-mux
sudo timeout 10 bash -c \
  "until dmesg | grep 'softdog: initialized. soft_noboot=1' >/dev/null; do sleep 0.2; done"
sudo systemctl start pve-ha-crm pve-ha-lrm
```

L'ultima riga deve riportare `soft_noboot=1`. Con questa opzione un nodo che
perde il quorum registra `softdog: Triggered - Reboot ignored` invece di
riavviarsi: il fencing resta un esercizio di comportamento, come spiegato in
`docs/proxmox.md`. Su bare metal, o su un hypervisor che non mette in pausa il
guest, lasciare il watchdog nella configurazione predefinita.

Verificare su ogni nodo:

```bash
hostname --fqdn
getent hosts pve1 pve2 pve3
getent hosts "$(hostname --short)"
sudo test -d "/etc/pve/nodes/$(hostname --short)"
sudo test ! -e /etc/pve/nodes/proxmox-template
```

L'ultima riga deve restituire l'indirizzo `192.168.56.x` del nodo corrente.

## 4. Installare rete persistente, NTP e prerequisiti

Prima di sostituire il gestore di rete aggiornare gli indici e installare tutti
i componenti necessari:

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl gnupg chrony sudo openssh-server \
  ifupdown2 isc-dhcp-client
sudo systemctl enable --now chrony
command -v dhclient
```

`ifupdown2` è il gestore raccomandato da Proxmox e permette successivamente di
applicare modifiche con `ifreload`. `isc-dhcp-client` è installato esplicitamente
perché la NIC NAT deve continuare a ottenere un lease dopo il passaggio da
`systemd-networkd`. Se si perde la NAT, si perdono sia SSH Vagrant sia accesso
ai repository.

chrony mantiene gli orologi dei nodi allineati. Corosync e i log distribuiti
dipendono da una misura temporale coerente per diagnosi e ordinamento degli
eventi.

## 5. Creare il bridge management `vmbr0`

Sostituire per intero `/etc/network/interfaces` su ogni nodo: la NIC NAT
passa da porta di `vmbr0` a interfaccia DHCP autonoma, e `vmbr0` diventa il
bridge management senza gateway. Il seguente è il modello per `pve1`;
sostituire `<NIC_NAT>` e `<NIC_MANAGEMENT>` con i nomi annotati prima:

```text
auto lo
iface lo inet loopback

auto <NIC_NAT>
iface <NIC_NAT> inet dhcp

iface <NIC_MANAGEMENT> inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.56.11/24
    bridge-ports <NIC_MANAGEMENT>
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
```

Su `pve2` e `pve3` cambia soltanto `address`, rispettivamente in
`192.168.56.12/24` e `192.168.56.13/24`.

L'IP appartiene al bridge, non alla NIC fisica che ne diventa una porta. Le VM
annidate collegate a `vmbr0` si comportano come dispositivi sullo stesso switch
virtuale. STP è disattivato perché questa topologia non contiene percorsi
ridondanti; il bridge è VLAN-aware per consentire esercizi successivi.

Su `vmbr0` non configurare gateway o DNS. La rete host-only non ha un router e
la default route deve restare sulla NAT. Prima del riavvio controllare:

```bash
sudo ifquery --list
command -v dhclient
ip route show default
```

Se il file contiene placeholder o nomi NIC errati, correggerlo prima di
proseguire. Preparare poi il cambio di gestore e riavviare un nodo alla volta:

```bash
sudo systemctl disable systemd-networkd.service systemd-networkd.socket
sudo systemctl enable networking
sudo reboot
```

La sessione SSH si chiuderà. Dal Bosgame attendere e riconnettersi:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Verificare prima di passare al nodo successivo:

```bash
ip -br address
ip route
ping -c 3 192.168.56.12
getent hosts pve2
curl -I https://www.proxmox.com/
chronyc tracking
```

Il ping verso gli altri nodi funzionerà solo dopo aver configurato anche loro.
Devono esserci `192.168.56.x/24` su `vmbr0` e una sola default route sulla NAT.

## 6. Aggiungere il repository Proxmox VE 9.2 (solo Debian pulita)

Con i cloni della box locale saltare questa sezione: repository e PVE sono già
presenti. Su Debian pulita eseguire quanto segue su tutti e tre i nodi.
Scaricare il keyring dedicato a Debian Trixie:

```bash
sudo curl -fsSL \
  https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
  -o /usr/share/keyrings/proxmox-archive-keyring.gpg
sha256sum /usr/share/keyrings/proxmox-archive-keyring.gpg
```

Per il file distribuito all'installazione iniziale, la documentazione ufficiale
indica SHA-256:

```text
136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45
```

Se il valore differisce, fermarsi e verificare la documentazione corrente: una
versione successiva del pacchetto keyring può aggiornare legittimamente il file,
ma non va accettata una chiave inattesa senza verifica.

Creare `/etc/apt/sources.list.d/infra-pve.list`:

```text
deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription
```

Il repository `pve-no-subscription` è adatto a valutazione e laboratorio; non ha
lo stesso livello di validazione del repository enterprise. Il percorso
`signed-by` limita la chiave a questa sorgente APT.

Per mantenere il ramo scelto dal laboratorio, creare
`/etc/apt/preferences.d/infra-pve`:

```text
Package: proxmox-ve pve-manager
Pin: version 9.2.*
Pin-Priority: 1000

Package: proxmox-ve pve-manager
Pin: version *
Pin-Priority: -1
```

Aggiornare gli indici e controllare origine e versione candidata:

```bash
sudo apt-get update
apt-cache policy proxmox-ve pve-manager proxmox-default-kernel
```

Il pin riguarda i metapacchetti principali e consente le patch `9.2.x`; non
rende l'intero sistema una build bit-per-bit.

## 7. Installare e avviare il kernel PVE (solo Debian pulita)

Con la box locale il kernel PVE è già installato; passare alla sezione 8. Su
Debian pulita, eseguire su ciascun nodo:

```bash
sudo apt-get install -y proxmox-default-kernel
sudo reboot
```

Riconnettersi sempre con il file manuale e verificare:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
uname -r
```

Il nome del kernel deve terminare in `-pve`. Installare prima il kernel e
riavviare separa due possibili problemi: avvio del kernel Proxmox e installazione
dello stack applicativo. Non rimuovere ancora il kernel Debian: nel laboratorio
è una possibilità di ripristino se il nuovo kernel non parte.

## 8. Verificare la virtualizzazione annidata

Con il kernel PVE attivo:

```bash
sudo modprobe kvm_amd
test -c /dev/kvm && echo KVM_OK
lsmod | grep -E '^kvm(_amd)?'
dmesg | grep -iE 'kvm|svm' | tail -n 20
```

`/dev/kvm` è il requisito che permette al Proxmox eseguito dentro VirtualBox di
avviare a sua volta VM accelerate. Se manca, non proseguire dando per operativo
il nodo: controllare SVM nel firmware, impostazione `nested-hw-virt` della VM e
conflitti fra VirtualBox e KVM sull'host.

Prima di creare il cluster, lasciare ogni nodo acceso per alcuni minuti e
verificare più volte SSH, data e UI. Sul Bosgame con VirtualBox 7.2.18 e nested
AMD-V è stato riprodotto uno stall con log `TM: Giving up catch-up attempt` e
circa 60 secondi di ritardo. `--virt-vmsave-vmload off` non lo ha risolto;
disabilitare nested AMD-V rende stabile il boot ma elimina `/dev/kvm`, quindi
non costituisce una soluzione per questi laboratori. Se il difetto ricompare,
fermarsi prima di cluster, Ceph o VM annidate e conservare `VBox.log`.

## 9. Installare Proxmox VE o ripristinare gli storage locali

Su Debian pulita, preconfigurare Postfix per uso locale ed evitare richieste interattive:

```bash
echo 'postfix postfix/main_mailer_type select Local only' | \
  sudo debconf-set-selections
echo 'postfix postfix/mailname string lab.test' | \
  sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  'proxmox-ve=9.2.*' 'pve-manager=9.2.*' postfix open-iscsi chrony
```

Il metapacchetto `proxmox-ve` installa i componenti coordinati della piattaforma;
`pve-manager` fornisce gestione e UI. `open-iscsi` prepara il nodo per esercizi
con storage a blocchi; Postfix locale gestisce le notifiche senza configurare un
relay esterno.

Verificare:

```bash
pveversion -v
systemctl --failed
systemctl status pveproxy pvedaemon pvestatd --no-pager
ss -ltnp | grep ':8006'
```

Con la box locale non reinstallare i pacchetti. Il reset dell'identità ha creato
un nuovo database `pmxcfs`, quindi registrare nuovamente gli storage realizzati
dall'installer ISO. In entrambi i percorsi controllare prima lo stato:

```bash
sudo pvesm status
df -h /var/lib/vz
```

Se non esiste `local`, aggiungerlo esplicitamente:

```bash
sudo pvesm add dir local --path /var/lib/vz \
  --content iso,vztmpl,backup
```

Con la box ISO verificare anche `sudo lvs pve/data` e, se il volume esiste ma
`local-lvm` manca, registrarlo:

```bash
sudo pvesm add lvmthin local-lvm --vgname pve --thinpool data \
  --content images,rootdir
```

Entrambi gli storage risiedono sul disco OS del singolo nodo: non sono condivisi
né ridondati.

## 10. Impostare l'accesso amministrativo e verificare la UI

La box Vagrant normalmente usa `sudo` e non fornisce una password root utile per
la UI. Impostarla interattivamente su ogni nodo, senza scriverla nel repository:

```bash
sudo passwd root
```

Aprire dal Bosgame:

- `https://192.168.56.11:8006`
- `https://192.168.56.12:8006`
- `https://192.168.56.13:8006`

Accedere come `root` nel realm **Linux PAM**. Il certificato iniziale è
autofirmato: l'avviso del browser è atteso nel laboratorio, ma bisogna comunque
controllare di essere sull'IP corretto.

Prima del cluster, verificare da ogni nodo:

```bash
uname -r
test -c /dev/kvm && echo KVM_OK
ip -br address
ip route
getent hosts pve1 pve2 pve3
chronyc tracking
pveversion
```

Non creare il cluster finché tutti e tre i nodi non superano questi controlli.

## 11. Creare il cluster e unire i nodi

Su `pve1`, entrare in una shell root e creare il cluster `study`, vincolando il
primo link Corosync all'indirizzo management:

```bash
sudo -i
pvecm create study --link0 192.168.56.11
pvecm status
exit
```

Su `pve2`:

```bash
sudo -i
pvecm add 192.168.56.11 --link0 192.168.56.12
exit
```

Su `pve3`:

```bash
sudo -i
pvecm add 192.168.56.11 --link0 192.168.56.13
exit
```

Durante il join verificare il fingerprint mostrato e fornire la password root di
`pve1`. Il join distribuisce configurazione e chiavi tramite `pmxcfs`; per questo
i nodi da aggiungere devono essere vuoti.

Da un nodo qualsiasi controllare:

```bash
sudo pvecm nodes
sudo pvecm status
sudo systemctl status corosync --no-pager
```

Il risultato atteso è tre nodi, tre voti e quorum acquisito. Il cluster usa una
sola rete perché questo lab privilegia semplicità e osservabilità, non resilienza
di rete.

## 12. Fault test del quorum

Dal Bosgame arrestare ordinatamente un solo nodo:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt pve3
```

Su `pve1` verificare:

```bash
sudo pvecm status
sudo pvecm nodes
```

Con due nodi su tre il cluster deve restare quorate. Non spegnere anche `pve2`:
un solo voto non costituisce la maggioranza e `/etc/pve` diventa di norma
sola lettura per proteggere la consistenza.

Riaccendere `pve3` e attendere che rientri:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up pve3
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve3
sudo pvecm status
```

Non modificare artificialmente gli expected votes: il test serve a osservare il
meccanismo di sicurezza, non ad aggirarlo.

## 13. Creare una VM annidata e provarne la migrazione

Prima controllare lo spazio reale con `df -h /var/lib/vz`. Nella UI, sotto
Datacenter → Storage → `local`, abilitare anche **Disk image** e **Container**.

1. Caricare una piccola ISO Linux su `local` di `pve1`.
2. Creare la VM 100 con 2 vCPU, 2 GiB RAM, disco 12 GiB e NIC VirtIO su `vmbr0`.
3. Usare inizialmente un tipo CPU uguale sui tre nodi, per esempio `host` in
   questo lab omogeneo.
4. Assegnare alla VM un IP libero, per esempio `192.168.56.101/24`, senza
   gateway. La rete host-only non offre automaticamente accesso Internet.
5. Dopo l'installazione smontare l'ISO, che altrimenti resta un file locale del
   nodo sorgente.

Avviare un ping continuo dal Bosgame, poi da `pve1`:

```bash
sudo qm migrate 100 pve2 --online --with-local-disks
```

`--with-local-disks` copia il disco mentre la VM è attiva. Osservare task,
durata, breve perdita di pacchetti ed effettiva posizione finale del disco.
Questa operazione è una migrazione esplicita: non trasforma lo storage locale in
storage condiviso.

## 14. Limiti dell'HA in questo laboratorio

Il cluster può mostrare quorum e servizi HA, ma una VM con disco presente solo
sul nodo guasto non può essere riavviata altrove. La precedente migrazione copia
il disco perché il nodo sorgente è ancora disponibile; un guasto improvviso non
offre questa possibilità.

Per un vero esercizio di restart HA usare il laboratorio Proxmox Ceph, dove il
disco della VM è accessibile dai nodi superstiti. Anche lì il fencing virtuale è
un'approssimazione didattica e non sostituisce un BMC/IPMI reale.

## Arresto, ripresa e reset

Prima di spegnere il lab, arrestare ordinatamente tutte le VM e gli eventuali
container annidati. Poi, dal Bosgame:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt
```

Alla ripresa:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
sudo pvecm status
```

Attendere il ritorno di tutti i nodi e del quorum prima di modificare risorse.
Evitare snapshot e ripristini indipendenti dei singoli membri di un cluster.

Per eliminare definitivamente nodi, cluster e VM annidate:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```

`destroy` è un reset distruttivo e richiede conferma. Non alternare
`Vagrantfile.start` e `Vagrantfile` sulle stesse istanze: per cambiare percorso
salvare prima gli appunti, distruggere con il file usato per creare le VM e solo
in seguito avviare l'altro percorso.

## Riferimenti

- [Proxmox VE: installazione sopra Debian 13 Trixie](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie)
- [Proxmox VE Administration Guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf)
- [Proxmox VE: configurazione di rete e bridge](https://pve.proxmox.com/wiki/Network_Configuration)
- [Proxmox VE: repository dei pacchetti](https://pve.proxmox.com/wiki/Package_Repositories)
- [Runbook comune del repository](../docs/proxmox.md)
