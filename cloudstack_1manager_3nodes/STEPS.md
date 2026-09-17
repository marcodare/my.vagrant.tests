# Percorso manuale: CloudStack semplice

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant usare un manager e tre host KVM Ubuntu 22.04 puliti, con
virtualizzazione esposta sui KVM. Servono una rete public simulata, una rete
privata/VLAN e un uplink per repository; adattare IP, bridge e NIC senza
cambiare i traffic type. Preparare DNS, NTP, SSH e un disco primary vuoto per
ogni KVM. Conservare password e chiavi soltanto localmente.

`Vagrantfile.start` crea le stesse VM, CPU, RAM, NIC, MAC e dischi del percorso
assistito, ma non configura hostname, IP, pacchetti o servizi nel guest. I due
file condividono `.vagrant`: non alternarli sulle stesse istanze.

## 1. Avvio e inventario

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh manager
```

Inventariare su ogni nodo `ip -br link`, `ip -br address`, `ip route`, `lsblk`
e `df -hT`. La NIC 1 NAT conserva DHCP e default route. NIC 2 fake public e
NIC 3 private devono inizialmente essere prive di IPv4.

| Nodo | Fake public | Private | MAC NIC 2 | MAC NIC 3 |
| --- | --- | --- | --- | --- |
| `manager` | `192.168.60.10` | `10.60.0.10` | `08:00:27:3c:01:02` | `08:00:27:3c:01:03` |
| `kvm1` | `192.168.60.21` | `10.60.0.21` | `08:00:27:3c:02:02` | `08:00:27:3c:02:03` |
| `kvm2` | `192.168.60.22` | `10.60.0.22` | `08:00:27:3c:03:02` | `08:00:27:3c:03:03` |
| `kvm3` | `192.168.60.23` | `10.60.0.23` | `08:00:27:3c:04:02` | `08:00:27:3c:04:03` |

Il disco OS è da 80 GB. Ogni KVM ha inoltre un disco vuoto da 120 GB; non
assumere che sia `/dev/sdb` e non inizializzarlo prima di averne verificato
dimensione, seriale e assenza di filesystem.

## 2. Hostname, bridge e risoluzione

Su ciascun nodo impostare il proprio hostname. Creare un netplan come questo,
sostituendo nome, MAC e indirizzi; non aggiungere gateway o DNS ai bridge:

```yaml
network:
  version: 2
  ethernets:
    enplabpub:
      match: {macaddress: "08:00:27:3c:01:02"}
      set-name: enplabpub
      dhcp4: false
      dhcp6: false
    enplabpriv:
      match: {macaddress: "08:00:27:3c:01:03"}
      set-name: enplabpriv
      dhcp4: false
      dhcp6: false
  bridges:
    cloudbr1:
      interfaces: [enplabpub]
      addresses: [192.168.60.10/24]
      parameters: {stp: false, forward-delay: 0}
    cloudbr0:
      interfaces: [enplabpriv]
      addresses: [10.60.0.10/24]
      parameters: {stp: false, forward-delay: 0}
```

```bash
sudo hostnamectl set-hostname manager
sudo chmod 0600 /etc/netplan/60-infra-lab.yaml
sudo netplan generate
sudo netplan try
sudo netplan apply
```

Inserire su tutti i nodi i quattro nomi sulla rete privata:

```text
10.60.0.10 manager.lab.test manager
10.60.0.21 kvm1.lab.test kvm1
10.60.0.22 kvm2.lab.test kvm2
10.60.0.23 kvm3.lab.test kvm3
```

Installare `ca-certificates curl gnupg chrony sudo openssh-server`, abilitare
Chrony e verificare una sola default route sulla NAT, i due bridge, la
risoluzione dei nomi e i ping privati. `scripts/provision/base.sh` è il
riferimento esatto usato dal percorso assistito.

## 3. Manager, database, gateway e secondario

Sul manager aggiungere la chiave CloudStack e il repository Ubuntu `jammy 4.23`
con `signed-by`, quindi un pin che accetti soltanto `cloudstack-*` versione
`4.23.*`. Installare `cloudstack-management`, MySQL, NFS, dnsmasq e
`iptables-persistent`. Verificare con `apt-cache policy` e `dpkg-query -W` che
non sia stato installato un ramo differente.

Configurare MySQL come indicato in `scripts/provision/manager.sh`, riavviarlo e
creare segreti nuovi. Sostituire tutti i segnaposto, senza inserirli nel
repository o nella cronologia della shell:

```bash
sudo cloudstack-setup-databases \
  'cloud:<PASSWORD_DB>@localhost' \
  '--deploy-as=<UTENTE_DEPLOY>:<PASSWORD_DEPLOY>' \
  -e file -m '<MANAGEMENT_KEY>' -k '<DATABASE_KEY>' -i 10.60.0.10
sudo cloudstack-setup-management
```

L'account di deploy deve essere temporaneo e va eliminato dopo il setup.
Proteggere gli eventuali log perché il comando upstream riceve segreti negli
argomenti. Esportare `/srv/secondary` soltanto a `10.60.0.0/24` e verificare
con `exportfs -v`.

Abilitare IPv4 forwarding. Configurare NAT e forwarding dai bridge `cloudbr0`
e `cloudbr1` verso la NIC NAT, senza alterare la default route; salvare le regole
con netfilter-persistent. Configurare dnsmasq sui soli indirizzi
`192.168.60.10` e `10.60.0.10`. Verificare:

```bash
sudo systemctl --no-pager status mysql cloudstack-management nfs-kernel-server dnsmasq
sudo ss -lntup
sudo iptables-save
curl -I http://192.168.60.10:8080/client/
```

## 4. Host KVM e storage locale

Su ciascun KVM verificare prima `/dev/kvm`; se manca, fermarsi e correggere la
virtualizzazione annidata sull'host. Installare dal medesimo ramo 4.23
`cloudstack-agent`, QEMU/KVM, libvirt, client NFS e `uuid-runtime`. Configurare
`agent.properties` con:

```properties
private.network.device=cloudbr0
public.network.device=cloudbr1
guest.network.device=cloudbr0
local.storage.path=/var/lib/libvirt/images
guest.cpu.mode=host-passthrough
```

Seguire `scripts/provision/kvm.sh` per le opzioni libvirt e AppArmor, poi
verificare `virsh list --all`, lo stato dell'agent e i log. Per la registrazione
degli host impostare interattivamente una password temporanea a `vagrant` e
abilitare `PasswordAuthentication` soltanto nel lab isolato; provarla dal
manager sulla rete privata e rimuoverla quando non serve più.

Identificare il disco vuoto da 120 GB con un percorso `/dev/disk/by-id/`.
Soltanto dopo la verifica creare ext4 e montarlo su
`/var/lib/libvirt/images`, come descritto nel README. `mkfs` e `wipefs` sono
distruttivi: non usare mai il disco OS e non ripeterli su un lab popolato.

## 5. Template e zona Advanced

Importare sul secondario NFS il System VM template indicato dalla guida della
release installata. Per CloudStack 4.23 la documentazione attuale del progetto
indica il template 4.22.0; verificare sempre URL e checksum prima dell'import.

Creare dalla UI la zona Advanced con i valori del README: public su `cloudbr1`,
management/storage/guest su `cloudbr0`, system IP `10.60.0.50-79`, public pool
`192.168.60.100-199` e VLAN guest 100-199. Registrare i KVM tramite gli IP
privati, il secondary NFS `10.60.0.10:/srv/secondary` e i primary locali.
Abilitare `use.local.storage` e `system.vm.use.local.storage`; usare offering
locali e non presentare questo lab come storage condiviso.

## 6. Verifiche, fault test e reset

Verificare tre host `Up`, System VM `Running`, template disponibile, deploy di
una VM, DHCP/DNS/NAT guest e accesso tramite public IP. Testare snapshot e
restore. Spegnere un KVM dopo aver fermato o migrato i workload compatibili:
con primary locale non va atteso il riavvio HA della sua VM su un altro host.

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt kvm3
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up kvm3
```

Prima dell'arresto completo spegnere VM e System VM dalla UI, quindi:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up manager
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up kvm1 kvm2 kvm3
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```

`destroy` elimina database, dischi locali e VM annidate. Per passare al
percorso assistito distruggere prima usando ancora `Vagrantfile.start`, poi
avviare senza la variabile.

Fonti: [installazione manager](https://docs.cloudstack.apache.org/en/4.23.0.0/installguide/management-server/index.html),
[host KVM](https://docs.cloudstack.apache.org/en/4.23.0.0/installguide/hypervisor/kvm.html),
[reti](https://docs.cloudstack.apache.org/en/4.23.0.0/adminguide/networking.html) e
[storage](https://docs.cloudstack.apache.org/en/4.23.0.0/adminguide/storage.html).
