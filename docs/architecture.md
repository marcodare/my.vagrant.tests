# Architettura e convenzioni

## Topologia

Un solo lab acceso alla volta. Ogni cartella resta autonoma nello stato Vagrant;
ogni cartella è autosufficiente e può essere copiata da sola.

| Lab | Management / vmbr0 | Reti interne VirtualBox |
| --- | --- | --- |
| simple | 192.168.56.0/24 | nessuna |
| networks | 192.168.57.0/24 | 10.57.1.0/24 migrazione; 10.57.2.0/24 guest/VLAN |
| ceph | 192.168.58.0/24 | 10.58.1.0/24 Ceph |
| ceph_backup | 192.168.59.0/24 | 10.59.1.0/24 Ceph/backup |
| cloudstack | 192.168.60.0/24 su cloudbr0 | nessuna |

Management è **host-only**, accessibile dal Bosgame. Le reti aggiuntive sono
**internal network**, accessibili solo alle VM dello stesso lab. Nessuna rete è
bridged sulla LAN fisica. I range host-only rientrano in 192.168.56.0/21,
intervallo predefinito consentito da VirtualBox su Linux; non serve allargarne la
policy. Prima dell'avvio verificare assenza di sovrapposizioni con VPN/LAN.

La prima NIC resta NAT/DHCP per SSH e APT; non va usata per Corosync o Ceph.
NIC successive identificate tramite MAC, non assumendo nomi tipo eth1/enp0s8.
Promiscuous mode sulle NIC del lab permette il traffico dei MAC annidati.
Nessun gateway sulle NIC PVE interne. `vmbr0` e i bridge aggiuntivi sono VLAN-aware.

Le VM interne Proxmox, per default, comunicano nel lab senza Internet. Per un
esercizio che richiede Internet aggiungere un router virtuale, con uplink e NAT
espliciti; non modificare il bridge di management per tentativi.

## Risorse e storage

Risorse editabili in `lab.json`, a VM spente. CPU/RAM si applicano con `vagrant
reload`; ridurre un disco esistente non è supportato. La crescita del VDI non
garantisce la crescita del filesystem: verificare `lsblk` e `df -h` nel guest.
Le box Bento possono avere layout diversi: non assumere `/dev/sdb` o LVM.

Disco OS 80 GB per nodo. Ceph: un disco raw da 100 GB per nodo. PBS: 240 GB.
CloudStack: un disco locale da 120 GB per KVM; NFS secondario usa il disco OS
del manager (80 GB), sufficiente per pochi template di studio. Nessuna
formattazione automatica dei dischi aggiuntivi.

Vagrant gestisce creazione e rimozione dei dischi con il provider. Non spostare
VDI né cancellare `.vagrant` per tentare un reset. Le cartelle `disks/` sono
riservate a import manuali e documentazione; non contengono i VDI gestiti.

## Credenziali

Impostare la password root dei nodi PVE/PBS con `vagrant ssh <nodo>` e
`sudo passwd root`. Nessuna password condivisa generata o scritta nel repo.
CloudStack genera chiavi/password DB nel guest; il suo tool di setup riceve
segreti negli argomenti del processo e può scriverli nel log root-only.
Non condividere questi log. Per registrare gli host KVM usare `vagrant` con
password impostata interattivamente (vedere README CloudStack).

Le credenziali di bootstrap delle box sono proprie di ambienti Vagrant: tenere
le reti isolate. Non esporre le UI tramite port forwarding su tutte le interfacce.

## Nuovo laboratorio

1. Creare cartella descrittiva e scegliere subnet/MAC non sovrapposte.
2. Copiare e modificare il Vagrantfile autonomo e definire `lab.json`.
3. Mantenere tutti i provisioner nella cartella del lab; nessun import da shared/.
4. Documentare risorse, IP, avvio, provisioning, esercizi, stop, reset e limiti.
5. Aggiornare README, validatore del layout e la tabella delle reti.
6. Eseguire `./scripts/validate.sh`; sul Bosgame eseguire il collaudo reale.

Conservare in appunti di test le versioni rilevate da `VBoxManage --version`,
`vagrant --version`, `pveversion -v` e `dpkg-query -W 'cloudstack*'`.
