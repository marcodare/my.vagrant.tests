# cloudstack_1manager_3nodes

Per studiare tutto a mano usare `Vagrant.start` e seguire [STEPS.md](STEPS.md).
Il `Vagrantfile` mantiene il percorso assistito già disponibile.

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito
VAGRANT_VAGRANTFILE=Vagrant.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh manager
```

Nel percorso basic continuare con STEPS.md. Usare la variabile anche per
`status`, `halt` e `destroy`; non alternare i due file sulle stesse VM.

Un manager e tre KVM annidati su Ubuntu 22.04 / CloudStack 4.23. Due reti del
laboratorio, oltre alla NIC NAT tecnica Vagrant. Cartella autonoma: Vagrantfile,
lab.json e script locali sono modificabili senza dipendenze da altre cartelle.

## Reti e risorse

| Nodo | Fake public: cloudbr1 | Private: cloudbr0 | RAM | vCPU | Dischi GB |
| --- | --- | --- | --- | --- | --- |
| manager | 192.168.60.10 | 10.60.0.10 | 8 GiB | 4 | OS/NFS 80 |
| kvm1 | 192.168.60.21 | 10.60.0.21 | 16 GiB | 6 | OS 80 + locale 120 |
| kvm2 | 192.168.60.22 | 10.60.0.22 | 16 GiB | 6 | OS 80 + locale 120 |
| kvm3 | 192.168.60.23 | 10.60.0.23 | 16 GiB | 6 | OS 80 + locale 120 |

Fake public è host-only: accessibile dal Bosgame, non esposta sulla LAN/Internet.
Private è internal network VirtualBox: management dei nodi, NFS e trunk VLAN
guest. Management/storage sono untagged; le reti tenant usano VLAN 100–199.
Il manager fornisce DNS e gateway .10 sui due segmenti; la sua NAT consente
l'uscita Internet. Non collegare la NIC tecnica NAT alle reti CloudStack.

## Avvio e migrazione dalla vecchia topologia

Sul Bosgame già preparato con configure.host.sh, con gli altri lab spenti:

```bash
vagrant validate
./scripts/up.sh
```

**Se esiste già la precedente zona Basic:** la nuova zona è Advanced. Non
convertire in-place una zona popolata. Esportare ciò che serve, poi scegliere
esplicitamente `vagrant destroy` e ricreare il lab; il comando elimina tutti i
suoi dischi. Non viene eseguito automaticamente da alcuno script di aggiornamento.

Provisioning prepara bridge, pacchetti, DB, agent e NFS `/srv/secondary` sul
manager. Creazione zona, import template e formattazione disco restano esercizi.
UI: **http://192.168.60.10:8080/client**. Cambiare la password iniziale dell'app
al primo accesso (credenziali iniziali upstream admin/password).

## Preparare lo storage locale e l'accesso SSH

Su ogni KVM (`vagrant ssh kvm1`, poi kvm2/kvm3): verificare `/dev/kvm`,
`sudo virsh list --all`, `ip -br address`; impostare `sudo passwd vagrant`.
Per l'aggiunta dalla UI creare `/etc/ssh/sshd_config.d/00-infra-bootstrap.conf`
con `PasswordAuthentication yes`, poi `sudo sshd -t && sudo systemctl reload ssh`.
Dal manager provare `ssh vagrant@10.60.0.21` e gli altri nodi. Nessuna password
va salvata nel repository. Questa autenticazione serve solo al lab isolato.

Prima di aggiungere gli host, identificare il disco dati con
`lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL`. Deve essere il disco
vuoto **120 GB**, mai il disco OS. Da root, sostituire l'ID seguente con quello
verificato; mkfs è distruttivo e non deve essere ripetuto su un disco popolato:

```bash
disk=/dev/disk/by-id/INSERIRE_ID_DATI
lsblk "$disk"
wipefs --no-act "$disk"
mkfs.ext4 "$disk"
uuid=$(blkid -s UUID -o value "$disk")
printf 'UUID=%s /var/lib/libvirt/images ext4 defaults 0 2\n' "$uuid" >> /etc/fstab
mount /var/lib/libvirt/images
findmnt /var/lib/libvirt/images
```

## Importare System VM template

Sul manager: `dpkg-query -W cloudstack-management`. Selezionare il template previsto dalla documentazione 4.23 nel [catalogo ufficiale](https://download.cloudstack.org/systemvm/4.22/),
verificarne checksum e importarla con il tool seguente. La guida di installazione **4.23** indica il template **4.22.0**:

```bash
sudo /usr/share/cloudstack-common/scripts/storage/secondary/cloud-install-sys-tmplt \
  -m /srv/secondary \
  -u https://download.cloudstack.org/systemvm/4.22/systemvmtemplate-4.22.0-x86_64-kvm.qcow2.bz2 -h kvm
```

## Creare una zona Advanced

| Campo | Valore |
| --- | --- |
| Zona / pod / cluster | study / pod1 / kvm-cluster |
| Tipo | Advanced, senza security groups (reti isolate via router) |
| Physical network public | traffic Public, KVM label cloudbr1 |
| Physical network private | traffic Management, Storage, Guest; KVM label cloudbr0 |
| DNS esterno / interno | 192.168.60.10 / 10.60.0.10 |
| Pod gateway / netmask | 10.60.0.10 / 255.255.255.0 |
| Pod reserved/system IP | 10.60.0.50–10.60.0.79 |
| Public VLAN | untagged |
| Public gateway / netmask | 192.168.60.10 / 255.255.255.0 |
| Public allocation pool | 192.168.60.100–192.168.60.199 |
| Guest isolation | VLAN 100–199 sulla physical network private |
| Host KVM | 10.60.0.21, .22, .23; user vagrant |
| Secondary storage | NFS 10.60.0.10, path /srv/secondary |

Abilitare `use.local.storage` e `system.vm.use.local.storage` per la zona.
Usare compute offering con Storage type Local. I tre primary locali devono
comparire sul rispettivo host; non aggiungere primary NFS al loro posto.
Non attivare DHCP VirtualBox sulla fake public: gli IP pubblici sono assegnati
agli apparati CloudStack. Le reti guest hanno subnet distinte, per esempio
172.20.100.0/24, e DHCP/NAT forniti dai virtual router.

## Esercizi e arresto

1. Verificare tre host Up, System VM Running, template disponibile su NFS.
2. Creare rete guest isolata e VM; controllare DHCP, DNS e uscita via virtual router.
3. Allocare un public IP e configurare port forwarding/ACL SSH: accedere dal
   Bosgame all'IP fake public. L'IP guest non è direttamente raggiungibile dall'host.
4. Provare snapshot/restore. Il primary locale limita migrazione e HA; usare
   i nuovi lab distribuiti per confrontare il comportamento.

Spegnere istanze/System VM dalla UI, poi `vagrant halt`. Riprendere con
`vagrant up manager` seguito da `vagrant up kvm1 kvm2 kvm3`.
Collaudo end-to-end sul Bosgame ancora da eseguire.

Fonti: [KVM](https://docs.cloudstack.apache.org/en/4.23.0.0/installguide/hypervisor/kvm.html),
[reti](https://docs.cloudstack.apache.org/en/4.23.0.0/adminguide/networking.html).
