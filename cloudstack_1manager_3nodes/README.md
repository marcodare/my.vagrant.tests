# cloudstack_1manager_3nodes

CloudStack ramo 4.20 su Ubuntu 22.04: un manager con MySQL, DNS/router e NFS
secondario, tre host KVM annidati con storage locale. Solo questo laboratorio
acceso. `Vagrantfile`, `lab.json` e `scripts/provision/` sono autonomi e
modificabili: la cartella si può copiare da sola su un host già preparato.

## Topologia

| Nodo | IP su cloudbr0 | vCPU | RAM | Dischi |
| --- | --- | --- | --- | --- |
| manager | 192.168.60.10 | 4 | 8 GiB | OS/NFS 80 GB |
| kvm1 | 192.168.60.21 | 6 | 16 GiB | OS 80 + locale 120 GB |
| kvm2 | 192.168.60.22 | 6 | 16 GiB | OS 80 + locale 120 GB |
| kvm3 | 192.168.60.23 | 6 | 16 GiB | OS 80 + locale 120 GB |

RAM totale 56 GiB. Ogni VM ha NIC NAT tecnica per SSH/download. `cloudbr0`
connette management, guest e NFS. Il manager inoltra il traffico delle VM
annidate verso la propria NIC NAT e offre DNS su .10, senza DHCP.

## Avvio

Prerequisiti: host amd64 configurato con `configure.host.sh` dalla radice,
SVM abilitato, VirtualBox 7.2 e Vagrant. Dalla cartella:

```bash
vagrant validate
./scripts/up.sh
vagrant ssh manager
sudo systemctl status cloudstack-management
```

Provisioning installa pacchetti, database, manager, agent, bridge, routing/DNS e
export NFS `/srv/secondary`. Zona, host, template e formattazione dei dischi
restano i passaggi di studio descritti sotto. Non rilanciare provisioning dopo
aver personalizzato agent/reti senza voler ripristinare la base.

## 1. Preparare i tre host

Su ciascun KVM con `vagrant ssh kvm1` (poi kvm2/kvm3):

```bash
test -c /dev/kvm && echo KVM_OK
sudo virsh list --all
ip -br address
sudo passwd vagrant
```

Per la registrazione dalla UI abilitare password SSH **solo nell'ambiente di
studio**, creando `/etc/ssh/sshd_config.d/00-infra-bootstrap.conf` con:

```text
PasswordAuthentication yes
```

Quindi `sudo sshd -t && sudo systemctl reload ssh`. Dal manager verificare
`ssh vagrant@192.168.60.21` e gli altri due. L'utente vagrant della box ha sudo;
CloudStack può usarlo per registrare gli host. Non scrivere password nel repo.

Preparare il disco locale **prima** di aggiungere l'host a CloudStack:

```bash
sudo lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
```

Identificare il disco vuoto da **120 GB**, separato dal disco OS. Da shell root,
sostituire il percorso di esempio con quello verificato. Il comando mkfs è
distruttivo, non va ripetuto su un disco già popolato:

```bash
disk=/dev/disk/by-id/INSERIRE_ID_DISCO_DATI
lsblk "$disk"
wipefs --no-act "$disk"       # deve essere vuoto
mkfs.ext4 "$disk"
uuid=$(blkid -s UUID -o value "$disk")
printf 'UUID=%s /var/lib/libvirt/images ext4 defaults 0 2\n' "$uuid" >> /etc/fstab
mount /var/lib/libvirt/images
findmnt /var/lib/libvirt/images
```

Non usare `nofail`: se il disco manca è meglio un errore esplicito che scrivere
per sbaglio sul filesystem root. Il path è già configurato negli agent.

## 2. Importare il template delle System VM

Sul manager verificare la release installata:

```bash
dpkg-query -W cloudstack-management
df -h /srv/secondary
showmount -e 192.168.60.10
```

Usare il template KVM corrispondente alla release installata, prendendo URL e
checksum dal [catalogo System VM](https://download.cloudstack.org/systemvm/4.20/).
Il ramo APT può ricevere nuove patch: non scegliere a caso il primo template.
Esempio per **4.20.2** (adattare se la versione installata è differente):

```bash
sudo /usr/share/cloudstack-common/scripts/storage/secondary/cloud-install-sys-tmplt \
  -m /srv/secondary \
  -u https://download.cloudstack.org/systemvm/4.20/systemvmtemplate-4.20.2-x86_64-kvm.qcow2.bz2 \
  -h kvm
```

Attendere il completamento prima di creare la zona. Non usare `-F` su template
già importati durante semplici riavvii. I pacchetti sono convenience binaries
pubblicati dalla comunità CloudStack, con verifica APT della firma attiva.

## 3. Creare la zona dalla UI

Aprire **http://192.168.60.10:8080/client** dal Bosgame. Primo accesso con le
credenziali iniziali dell'applicazione (`admin` / `password`), quindi cambiare
subito la password. Non sono credenziali personalizzate del progetto.

Creare una **zona Basic**, un pod, un cluster KVM, usando:

| Campo | Valore |
| --- | --- |
| Zona / pod / cluster | study / pod1 / kvm-cluster |
| DNS e internal DNS | 192.168.60.10 |
| Gateway | 192.168.60.10 |
| Netmask | 255.255.255.0 |
| Pod reserved/system IP | 192.168.60.50–192.168.60.79 |
| Guest IP range | 192.168.60.100–192.168.60.199 |
| Guest gateway / netmask | 192.168.60.10 / 255.255.255.0 |
| Traffic label KVM | cloudbr0 per management/guest/storage |
| Hypervisor | KVM |
| Host | 192.168.60.21, poi .22 e .23 |
| SSH user | vagrant, password impostata sul singolo nodo |
| Secondary storage | NFS, server 192.168.60.10, path /srv/secondary |

Abilitare **Local storage** nelle opzioni della zona (`use.local.storage`) e
`system.vm.use.local.storage` per le System VM; se richiesto dalla UI riavviare
il management prima di abilitare la zona. Saltare l'aggiunta di primary NFS:
il primary locale viene rilevato dagli host. Verificare tre storage locali,
uno per host, con path `/var/lib/libvirt/images`. Creare una compute offering
con **Storage type = Local** per le istanze di prova.

Controllare che VirtualBox non abbia un DHCP attivo su questa stessa rete:
il DHCP guest verrà gestito da CloudStack. Non usare gli IP riservati .50–.79
o .100–.199 per altre VM manuali. Lasciare il manager acceso quando il lab è attivo.

## 4. Collaudo ed esercizi

1. Tre host **Up**, secondary storage disponibile, System VM **Running**.
2. Registrare ISO/template Linux, creare istanza con offering Local da 2 GiB.
3. Consentire ICMP/SSH nel security group per l'accesso dal segmento del lab;
   verificare console, DHCP, DNS e uscita Internet della VM.
4. Osservare il disco in primary locale e template/snapshot in secondario NFS.
5. Provare snapshot e ripristino; confrontare primary locale e storage condiviso.
   La migrazione/HA con disco locale ha vincoli: non aspettarsi il comportamento
   del lab Proxmox con RBD condiviso.

## Stop e reset

Arrestare istanze e System VM dalla UI prima di `vagrant halt`. Alla ripresa
avviare prima il manager, poi i KVM:

```bash
vagrant up manager
vagrant up kvm1 kvm2 kvm3
```

`vagrant destroy` elimina database, NFS secondario e dischi locali: reset totale.
Non è necessario distruggere il lab per provare un'altra infrastruttura.

## Stato e fonti

Prima implementazione sottoposta a controlli statici, da collaudare sul Bosgame.
Log: `/var/log/cloudstack/management/` e `/var/log/cloudstack/agent/`; il log
DB bootstrap è root-only e può contenere segreti, non condividerlo.

[Installazione manager](https://docs.cloudstack.apache.org/en/4.20.2.0/installguide/management-server/index.html),
[configurazione KVM](https://docs.cloudstack.apache.org/en/4.20.2.0/installguide/hypervisor/kvm.html).
