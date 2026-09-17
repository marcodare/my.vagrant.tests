# Percorso manuale: Proxmox VE mononodo

Questa è la procedura autorevole per ottenere un singolo nodo Proxmox VE 9.2
standalone. Con Vagrant si parte dalla box `local/proxmox-ve-9.2`, nella quale
PVE e il kernel sono già installati; `Vagrantfile.start` usa la stessa
definizione di VM, NIC, MAC, risorse e disco del percorso assistito, ma non
dichiara gli script di provisioning. Le sezioni dedicate a Debian 13 permettono
di adattare la stessa procedura a una VM generica o al bare metal.

Il risultato non è un cluster: non creare Corosync e non eseguire `pvecm create`.
L'obiettivo è verificare il singolo hypervisor prima di aggiungere complessità.

## Risultato atteso

| Nodo | IP management | MAC management | vCPU | RAM | Disco OS |
| --- | --- | --- | --- | --- | --- |
| `pve1` | `192.168.68.11/24` | `08:00:27:44:01:02` | 6 | 12 GiB | 80 GB |

Il nodo usa:

- NIC 1 NAT/DHCP per SSH Vagrant, repository, DNS e NTP;
- NIC 2 host-only come porta di `vmbr0`, senza gateway;
- hostname `pve1.lab.test` risolto sull'IP management;
- kernel PVE e `/dev/kvm` per la virtualizzazione annidata;
- storage locali `local` e, se presente il thin pool LVM, `local-lvm`.

Fuori da Vagrant sostituire IP, MAC e nomi NIC. Su bare metal è normale usare
un'unica NIC come porta di `vmbr0` e mettere sul bridge anche gateway e DNS: non
copiare il modello NAT/host-only se la rete reale ha un design diverso. Mantenere
sempre un accesso console mentre si cambia la rete.

## 1. Prerequisiti e cautele

- Sul Bosgame preparare l'host con `configure.host.sh` e spegnere gli altri lab.
- Abilitare SVM/AMD-V nel firmware e nested virtualization in VirtualBox.
- Costruire e aggiungere la box come descritto in
  `../create_boxes/proxmox/README.md`.
- Non eseguire i comandi destinati al guest sull'host Ubuntu.
- Non eliminare `config.db` su un nodo già configurato o contenente guest.
- Conservare una console prima di modificare rete, kernel o hostname.

Per un'installazione generica servono Debian 13 amd64 pulita, almeno 6 vCPU,
12 GiB RAM, 80 GB di disco, accesso ai repository e virtualizzazione hardware
esposta. Le risorse possono essere ridotte per prove leggere, ma una VM annidata
richiede memoria aggiuntiva.

## 2. Creare il clone basic

Dalla cartella `proxmox_singlenode`:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Usare la stessa variabile per ogni comando di questo percorso. I due file
condividono la directory di stato `.vagrant`: senza la variabile Vagrant carica
la definizione assistita e può operare sulla stessa macchina con i provisioner
dichiarati da quel file.

## 3. Rilevare lo stato iniziale

Nel guest, prima delle modifiche:

```bash
cat /etc/os-release
hostnamectl
ip -br link
ip -br address
ip route
cat /etc/resolv.conf
bridge link
lscpu | grep -E 'Architecture|Virtualization'
lsblk
df -hT
```

Con la box locale verificare anche:

```bash
pveversion
uname -r
hostname -s
sudo test ! -e /etc/pve/corosync.conf
```

Il ramo deve essere 9.2, il kernel deve terminare in `-pve`, l'hostname iniziale
deve essere `proxmox-template` e non deve esistere un cluster. L'installer della
box collega inizialmente la NIC NAT a `vmbr0`, con IP `10.0.2.15/24` e gateway
`10.0.2.2`; la seconda NIC è presente ma non configurata.

Identificare le interfacce senza presumere nomi come `enp0s3` o `enp0s8`:

```bash
ip -o link
ip route show default
bridge link
```

Annotare la porta fisica dell'attuale `vmbr0` come `<NIC_NAT>` e la NIC con MAC
`08:00:27:44:01:02` come `<NIC_MANAGEMENT>`. Su Debian generica, dove il bridge
iniziale può non esistere, la NIC NAT/uplink è quella della default route.

Il VDI è impostato a 80 GB, ma partizione e filesystem possono essere più
piccoli. Non assumere che la crescita del supporto abbia esteso il filesystem.

## 4. Finalizzare l'identità del clone PVE

Questa sezione vale soltanto per la box locale e deve essere eseguita prima di
creare VM o container. Preparare `/etc/hosts` rimuovendo le righe che citano
`proxmox-template` e aggiungendo:

```text
# BEGIN INFRA LAB
192.168.68.11 pve1.lab.test pve1
# END INFRA LAB
```

Poi verificare che il nodo sia vuoto e rigenerare la sua identità:

```bash
sudo test ! -e /etc/pve/corosync.conf
sudo find /etc/pve/nodes -type f \
  \( -path '*/qemu-server/*.conf' -o -path '*/lxc/*.conf' \) -print
# Il comando find non deve stampare nulla.

sudo systemctl stop pve-ha-lrm pve-ha-crm pvescheduler \
  pvestatd pveproxy pvedaemon
sudo systemctl stop pve-cluster
if mountpoint -q /etc/pve; then echo '/etc/pve ancora montato'; exit 1; fi
sudo rm -f /var/lib/pve-cluster/config.db /var/lib/pve-cluster/config.db-*
sudo hostnamectl set-hostname pve1
sudo systemctl start pve-cluster
sudo pvecm updatecerts --force
sudo systemctl start pvedaemon pveproxy pvestatd pvescheduler \
  pve-ha-crm pve-ha-lrm
```

La rimozione di `config.db` è sicura esclusivamente sul clone standalone vuoto:
genera CA, certificati e directory `/etc/pve/nodes/pve1` univoci. Su Debian
pulita impostare soltanto hostname e hosts, perché `pmxcfs` non è installato.

Nelle sole VM VirtualBox rendere `softdog` diagnostico per evitare che una pausa
del guest oltre i 10 secondi lo resetti durante il provisioning:

```bash
echo 'options softdog soft_noboot=1' | \
  sudo tee /etc/modprobe.d/infra-lab-softdog.conf
sudo systemctl stop pve-ha-lrm pve-ha-crm
sudo systemctl stop watchdog-mux
sudo modprobe -r softdog
sudo systemctl start watchdog-mux
sudo timeout 10 bash -c \
  "until dmesg | grep 'softdog: initialized. soft_noboot=1' >/dev/null; do sleep 0.2; done"
sudo systemctl start pve-ha-crm pve-ha-lrm
```

Il log deve contenere `soft_noboot=1`. Non applicare questa modifica su bare
metal: lì il watchdog può far parte del fencing reale.

Controllare infine:

```bash
hostname --fqdn
getent hosts pve1
sudo test -d /etc/pve/nodes/pve1
sudo test ! -e /etc/pve/nodes/proxmox-template
```

## 5. Installare rete persistente e prerequisiti

Installare prima gli strumenti necessari, mentre la rete iniziale funziona:

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl gnupg chrony sudo openssh-server \
  ifupdown2 isc-dhcp-client
sudo systemctl enable --now chrony
command -v dhclient
```

Sostituire `/etc/network/interfaces`, usando i nomi annotati al passo 3:

```text
auto lo
iface lo inet loopback

auto <NIC_NAT>
iface <NIC_NAT> inet dhcp

iface <NIC_MANAGEMENT> inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.68.11/24
    bridge-ports <NIC_MANAGEMENT>
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
```

L'IP appartiene al bridge, non alla sua porta. Non aggiungere gateway a `vmbr0`:
la default route deve restare sulla NAT. Sul bare metal adattare questo punto
alla rete reale e configurare gateway sul bridge solo se quello è l'uplink.

Prima del riavvio:

```bash
sudo ifquery --list
command -v dhclient
ip route show default
sudo systemctl disable systemd-networkd.service systemd-networkd.socket
sudo systemctl enable networking
sudo reboot
```

Dal Bosgame riconnettersi dopo il boot:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Verificare:

```bash
ip -br address
ip route
ping -c 3 192.168.68.1
curl -I https://www.proxmox.com/
chronyc tracking
```

Devono esserci `192.168.68.11/24` su `vmbr0` e una sola default route sulla
NIC NAT. L'adattatore host-only del Bosgame occupa normalmente `.1`.

## 6. Installare PVE da Debian 13 pulita

Saltare questa sezione con la box locale. Su Debian 13 scaricare il keyring e
verificarne l'impronta contro la documentazione ufficiale corrente:

```bash
sudo curl -fsSL \
  https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
  -o /usr/share/keyrings/proxmox-archive-keyring.gpg
sha256sum /usr/share/keyrings/proxmox-archive-keyring.gpg
```

Il valore documentato per il file iniziale Trixie è:

```text
136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45
```

Se differisce, fermarsi e controllare la documentazione ufficiale: un keyring
aggiornato può cambiare legittimamente, ma non va accettato senza verifica.

Creare `/etc/apt/sources.list.d/infra-pve.list`:

```text
deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription
```

Creare `/etc/apt/preferences.d/infra-pve`:

```text
Package: proxmox-ve pve-manager
Pin: version 9.2.*
Pin-Priority: 1000

Package: proxmox-ve pve-manager
Pin: version *
Pin-Priority: -1
```

Installare prima il kernel, riavviare e verificarlo:

```bash
sudo apt-get update
apt-cache policy proxmox-ve pve-manager proxmox-default-kernel
sudo apt-get install -y proxmox-default-kernel
sudo reboot
uname -r
```

Il kernel deve terminare in `-pve`. Preconfigurare quindi Postfix locale e
installare lo stack:

```bash
echo 'postfix postfix/main_mailer_type select Local only' | \
  sudo debconf-set-selections
echo 'postfix postfix/mailname string lab.test' | \
  sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  'proxmox-ve=9.2.*' 'pve-manager=9.2.*' postfix open-iscsi chrony
```

Il repository `pve-no-subscription` è adatto al laboratorio, non offre lo
stesso livello di validazione dell'enterprise repository. Il pin fissa i
metapacchetti al ramo 9.2 ma non produce una build bit-per-bit.

## 7. Verificare virtualizzazione e servizi

```bash
sudo modprobe kvm_amd
test -c /dev/kvm && echo KVM_OK
lsmod | grep -E '^kvm(_amd)?'
dmesg | grep -iE 'kvm|svm' | tail -n 20
pveversion -v
systemctl --failed
systemctl status pveproxy pvedaemon pvestatd --no-pager
ss -ltnp | grep ':8006'
sudo test ! -e /etc/pve/corosync.conf
```

Se `/dev/kvm` manca, non dichiarare operativo il nodo: controllare SVM nel
firmware, nested hardware virtualization della VM e conflitti KVM/VirtualBox
sull'host. L'assenza di `corosync.conf` conferma il funzionamento standalone.

## 8. Registrare gli storage locali

Il reset di `pmxcfs` può rimuovere le registrazioni create dall'installer.
Controllare prima di aggiungere qualsiasi storage:

```bash
sudo pvesm status
df -h /var/lib/vz
```

Se manca `local`:

```bash
sudo pvesm add dir local --path /var/lib/vz \
  --content iso,vztmpl,backup
```

Se `sudo lvs pve/data` mostra il thin pool ma manca `local-lvm`:

```bash
sudo pvesm add lvmthin local-lvm --vgname pve --thinpool data \
  --content images,rootdir
```

Non formattare dispositivi in base al solo nome `/dev/sdX`: identificare sempre
dimensione, seriale e contenuto con `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS`.

## 9. Accesso amministrativo e UI

Impostare la password senza salvarla in file o comandi del repository:

```bash
sudo passwd root
```

Aprire `https://192.168.68.11:8006` dal Bosgame e accedere come `root` nel
realm **Linux PAM**. L'avviso per il certificato autofirmato è atteso; verificare
comunque IP e fingerprint prima di accettarlo.

Checklist finale:

```bash
hostname --fqdn
getent hosts pve1
uname -r
test -c /dev/kvm && echo KVM_OK
ip -br address
ip route
chronyc tracking
sudo pveversion
sudo pvesm status
sudo test ! -e /etc/pve/corosync.conf
```

## 10. Creare una prima VM annidata

Verificare lo spazio con `df -h /var/lib/vz`. Nella UI caricare una piccola ISO
Linux in `local`, poi creare una VM di prova con 2 vCPU, 2 GiB RAM, disco 12 GiB,
CPU `host` e NIC VirtIO su `vmbr0`. Usare per esempio
`192.168.68.101/24` senza gateway.

La rete host-only non fornisce Internet al guest annidato. Un accesso esterno
richiede un router o NAT progettato esplicitamente; non spostare la default route
del nodo PVE su `vmbr0` per aggirare il limite.

Dopo l'installazione smontare l'ISO e verificare dal nodo:

```bash
sudo qm list
sudo qm status 100
ping -c 3 192.168.68.101
```

## 11. Fault test controllati

Questi test osservano il recupero del singolo nodo, non l'HA.

Riavviare il proxy web e verificare che la UI torni disponibile:

```bash
sudo systemctl restart pveproxy
sudo systemctl is-active pveproxy pvedaemon pvestatd
curl -kI https://127.0.0.1:8006/
```

Arrestare e riavviare la VM di prova, controllando che storage e configurazione
persistano:

```bash
sudo qm shutdown 100 --timeout 60
sudo qm status 100
sudo qm start 100
sudo qm status 100
```

Infine spegnere ordinatamente il guest annidato e il nodo dal Bosgame:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt pve1
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up pve1
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh pve1
```

Dopo il ritorno verificare `pveversion`, `/dev/kvm`, `pvesm status`, UI e stato
della VM. Un guasto reale del nodo rende indisponibili tutti i workload: non ci
sono repliche, quorum o failover in questo laboratorio.

## Arresto, ripresa e reset

Spegnere prima tutte le VM/LXC annidate. Per conservare lo stato:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
```

Reset distruttivo, solo quando si vogliono perdere nodo e guest annidati:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```

Non alternare il file manuale e quello assistito sulla stessa istanza: entrambi
condividono lo stato `.vagrant`. Per cambiare percorso, distruggere la macchina
con la stessa definizione usata per crearla e avviare poi l'altro percorso.

## Riferimenti

- [Proxmox VE: installazione sopra Debian 13 Trixie](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie)
- [Proxmox VE Administration Guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf)
- [Proxmox VE: configurazione di rete e bridge](https://pve.proxmox.com/wiki/Network_Configuration)
- [Proxmox VE: repository dei pacchetti](https://pve.proxmox.com/wiki/Package_Repositories)
- [Costruzione della box locale](../create_boxes/proxmox/README.md)
