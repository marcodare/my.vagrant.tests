# Box locale Proxmox VE 9.2 per VirtualBox

Builder riproducibile di una box Vagrant `amd64` installata dall'ISO ufficiale
Proxmox VE **9.2-1**. Packer governa VirtualBox da CLI, attende l'installazione
unattended, prepara l'accesso Vagrant e produce una `.box` locale.

La box non è ancora usata dai laboratori. Prima occorre collaudarla realmente
sul Bosgame e definire la finalizzazione dell'identità Proxmox per ogni clone.

## Cosa produce

- Proxmox VE installato dall'ISO ufficiale, con kernel PVE;
- disco SATA dinamico da 80 GB con layout LVM creato dall'installer;
- NIC 1 NAT/DHCP, necessaria al communicator Packer e a Vagrant;
- utente `vagrant`, chiave pubblica insecure e `sudo` senza password;
- repository `pve-no-subscription` per Debian 13/Trixie;
- nessuna Guest Addition e nessuna cartella sincronizzata;
- nessun cluster, VM, container, Ceph o storage aggiuntivo;
- `.box` in `output/`, esclusa da Git.

Versioni fissate:

| Componente | Valore |
| --- | --- |
| ISO | `proxmox-ve_9.2-1.iso` |
| SHA-256 ISO | `4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c` |
| Chiave release Trixie | `24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E` |
| Chiave release Bookworm | `F4E136C67CDCE41AE6DE6FC81140AF8F639E0C39` |
| Versione box | `9.2.1-1` |
| Provider | VirtualBox/amd64 |

La versione della box è distinta dalla versione dei pacchetti: `9.2.1-1`
significa ISO PVE `9.2-1`, revisione 1 del processo di packaging.

## Perché Packer

Il builder ufficiale `virtualbox-iso` crea e controlla una VM VirtualBox a
partire da un'ISO; il post-processor Vagrant esporta OVF e disco nel formato
`.box`. Questo mantiene visibili i comandi e i file di configurazione senza
reimplementare a mano gestione VM, port forwarding SSH, timeout ed export.

L'ISO viene trasformata con `proxmox-auto-install-assistant`, lo strumento
ufficiale che valida `answer.toml` e aggiunge all'immagine la modalità automated.
`build.sh` costruisce un piccolo container Debian 13 con il tool ufficiale e lo
esegue tramite Docker, evitando di aggiungere repository Proxmox all'host.

## Prerequisiti host

- Bosgame Ubuntu 26.04 amd64 preparato con `configure.host.sh`;
- VirtualBox 7.2 e Vagrant 2.4.x;
- Packer 1.14 o successivo;
- `gettext-base`, per `envsubst`;
- `gpg`, `gpgv`, `openssl`, `curl` e `sha256sum`;
- Docker Engine accessibile dall'utente corrente;
- nessuna altra VM VirtualBox accesa durante la build;
- almeno 15 GB liberi oltre allo spazio dinamico della VM temporanea.

Il repository HashiCorp configurato da `configure.host.sh` distribuisce anche
Packer. Docker deve essere già installato e accessibile; la preparazione
standard installa gli altri strumenti e ne verifica l'insieme:

```bash
sudo ./configure.host.sh
sudo reboot
./configure.host.sh --check
```

Non è necessario installare `proxmox-auto-install-assistant` sull'host. Il
container builder scarica pacchetti esclusivamente dal repository Proxmox
`pve-no-subscription` per Trixie e viene eliminato al termine di ogni comando;
l'immagine locale resta nella cache Docker per velocizzare le build successive.

## Sicurezza delle credenziali

La build richiede una password root temporanea perché Packer deve collegarsi
alla macchina appena installata. `build.sh` la chiede senza echo, la mantiene in
memoria e passa all'installer solo un hash SHA-512 crypt. La password:

- non compare nei file versionati;
- non viene passata come argomento della command line di Packer;
- non viene scritta nel file `answer.toml` in chiaro;
- viene bloccata nella box finale;
- l'autenticazione SSH tramite password viene nuovamente disabilitata;
- viene rimossa dall'ambiente al termine della build.

È possibile fornire `PROXMOX_BUILD_PASSWORD` dall'ambiente, ma l'inserimento
interattivo evita di salvarla nella history. Non riutilizzare una password reale.

La chiave privata insecure di Vagrant non viene letta o copiata dal builder.
Packer carica nel guest soltanto la chiave **pubblica** distribuita con
Vagrant; al primo `vagrant up`, Vagrant la sostituisce con una chiave generata
per l'istanza.

## 1. Controllo non distruttivo

Dalla cartella `create_boxes/proxmox`:

```bash
./scripts/build.sh --check
./scripts/validate.sh
```

Il primo comando controlla binari e chiave pubblica Vagrant. Il secondo verifica
gli script e, se Packer è disponibile, la formattazione HCL. Non vengono fatti
download e non viene avviata alcuna VM.

## 2. Preparare soltanto l'ISO unattended

Per collaudare download, firme e answer file senza avviare VirtualBox:

```bash
./scripts/build.sh --prepare-only
```

Il comando:

1. scarica ISO, firma e chiave release in `cache/`;
2. verifica SHA-256 dell'ISO;
3. verifica i fingerprint delle chiavi Trixie e Bookworm;
4. verifica entrambe le firme OpenPGP presenti nel file detached;
5. valida `answer.toml` con lo strumento Proxmox;
6. produce `cache/proxmox-ve_9.2-1.auto.iso`.

ISO, chiavi scaricate e file generati sono esclusi da Git. Un checksum o una
firma non validi interrompono la procedura.

## 3. Costruire la box

Con tutte le altre VM spente:

```bash
./scripts/build.sh
```

Per osservare la console dell'installer:

```bash
./scripts/build.sh --gui
```

Packer installa i plugin dichiarati, crea la VM temporanea, attende fino a 60
minuti SSH, esegue gli script guest, spegne la VM ed esporta:

```text
output/proxmox-ve-9.2.1-1-virtualbox-amd64.box
```

Il comando rifiuta di partire se rileva altre VM VirtualBox accese. `--force`
permette di sostituire un precedente output Packer; va usato solo quando si
intende ricostruire la stessa revisione.

## 4. Aggiungere la box a Vagrant

Questa operazione modifica il catalogo Vagrant dell'utente e non è eseguita
automaticamente dal builder:

```bash
vagrant box add \
  --name local/proxmox-ve-9.2 \
  --provider virtualbox \
  output/proxmox-ve-9.2.1-1-virtualbox-amd64.box
vagrant box list | grep 'local/proxmox-ve-9.2'
```

Una box aggiunta direttamente da file compare normalmente con versione `0`.
Non pubblicarla né copiarla fuori dal Bosgame senza avere prima verificato
assenza di credenziali, log e identità non desiderate.

## 5. Smoke test isolato

Il test deve essere eseguito senza altri lab accesi:

```bash
cd smoke
vagrant up
vagrant ssh -c 'sudo -n pveversion -v; uname -r; test -c /dev/kvm && echo KVM_OK'
vagrant halt
vagrant destroy
```

Il test usa soltanto la NAT e non cambia hostname o stato PVE. Confermare
manualmente prima di `destroy`, che elimina esclusivamente la VM smoke.

Verifiche minime attese:

- login SSH come `vagrant` e `sudo -n` funzionanti;
- kernel con suffisso `-pve`;
- versione Proxmox nel ramo 9.2;
- `/dev/kvm` presente con nested virtualization;
- nessuna appartenenza a un cluster;
- UI PVE e servizi principali attivi.

## Identità Proxmox nei laboratori

L'installer crea il nodo `proxmox-template.lab.test` e inizializza `pmxcfs`,
certificati PVE e directory `/etc/pve/nodes/proxmox-template`. La pulizia della
box rigenera in sicurezza `machine-id` e chiavi host SSH, ma non rinomina
automaticamente lo stato Proxmox.

I Vagrantfile assistiti dei laboratori Proxmox eseguono
`scripts/provision/finalize-pve.sh` prima di qualsiasi join. La finalizzazione:

1. assegni hostname e `/etc/hosts` definitivi prima dell'avvio operativo dei
   servizi PVE;
2. converta lo stato standalone dal nome template al nome del nodo;
3. rigeneri certificati PVE e verifichi `/etc/pve/nodes/<nome>`;
4. configuri NIC NAT e bridge management del singolo laboratorio;
5. verifica che i tre nodi abbiano identità distinte prima di consentire gli
   esercizi `pvecm create` e `pvecm add`.

Questa separazione è intenzionale: il builder produce l'artefatto di base;
i laboratori producono le identità finali. Il provisioner rifiuta di azzerare
`pmxcfs` se trova un cluster, una VM o un container preesistente. Anche il
percorso manuale `Vagrantfile.start` clona la box, ma non esegue
il provisioner: la stessa finalizzazione viene svolta a mano seguendo STEPS.md.

## Layout e file generati

```text
proxmox.pkr.hcl                     definizione Packer
answer.toml.pkrtpl                  risposta installer, senza password
box/Vagrantfile                     default incorporati nella box
containers/auto-assistant/          tool Proxmox in container
scripts/build.sh                    download, verifica e build
scripts/prepare-vagrant.sh          utente SSH e prerequisiti Vagrant
scripts/cleanup.sh                  pulizia prima dell'export
scripts/validate.sh                 controlli statici
smoke/Vagrantfile                   test isolato della box locale
cache/ output/ packer_cache/        artefatti locali ignorati
```

## Stato delle verifiche

La definizione può essere verificata staticamente senza modificare l'host. La
build completa, il boot dell'ISO automated, il packaging e lo smoke test devono
ancora essere eseguiti sul Bosgame. Fino ad allora la box non è dichiarata
operativa e nessun laboratorio deve dipenderne.

## Fonti

- [Download e verifica ISO Proxmox](https://enterprise.proxmox.com/iso/)
- [Proxmox VE Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
- [Proxmox VE Administration Guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.pdf)
- [Packer VirtualBox plugin](https://developer.hashicorp.com/packer/integrations/hashicorp/virtualbox)
- [Packer Vagrant post-processor](https://developer.hashicorp.com/packer/integrations/hashicorp/vagrant/latest/components/post-processor/vagrant)
- [Vagrant: creare una base box](https://developer.hashicorp.com/vagrant/docs/boxes/base)
- [Formato delle box VirtualBox](https://developer.hashicorp.com/vagrant/docs/providers/virtualbox/boxes)
