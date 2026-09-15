# zsvirt_1node_eval

Il percorso è manuale: usare `Vagrant.start` e seguire [STEPS.md](STEPS.md).
Il `Vagrantfile` originale resta disponibile per la preparazione dell'appliance.

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # appliance preparata
VAGRANT_VAGRANTFILE=Vagrant.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh zsvirt1
```

Nel percorso basic continuare con STEPS.md. Usare la variabile anche per
`status`, `halt` e `destroy`; non alternare i due file sulle stesse VM.

**Sì, è plausibile provarlo in VirtualBox con virtualizzazione annidata**, ma
la compatibilità specifica Bosgame/VirtualBox deve essere verificata. ZSvirt
pubblica una [procedura ufficiale per VM annidate](https://docs.zsvirt.io/en/docs/quick-start/nested-virtualization-management-node)
con immagini OVA/qcow2. Questo non equivale a una certificazione di VirtualBox.

## Quanti nodi

- **1 all-in-one** per conoscere UI, datastore, rete e creare la prima VM: è la
  scelta di questo lab, con 8 vCPU, 24 GiB RAM, OS 200 GB e dati 100 GB.
- **1 manager + 2 compute (3 VM totali)** come passo successivo per confrontare
  host e migrazioni, aggiungendo storage condiviso. Non basta storage locale.
- HA dei manager/storage richiede una topologia ulteriore, non è inclusa qui.

Il [quickstart](https://docs.zsvirt.io/en/docs/quick-start) ammette il percorso
all-in-one. Il manager si può registrare come host compute per la prima prova.

## Prerequisito esplicito: immagine e box locale

Non risulta una box Vagrant ufficiale verificata da usare direttamente. Il
Vagrantfile fa riferimento a **local/zsvirt-h84r**, che devi preparare a partire
dall'OVA ufficiale. Finché la box non esiste, `scripts/up.sh` si ferma con un
messaggio: non scarica una distribuzione diversa spacciandola per ZSvirt.

1. Scaricare l'OVA **x86_64 h84r** dal sito del progetto; verificarne checksum
   e provenienza. L'immagine non viene redistribuita in questo repository.
2. Importarla in VirtualBox con nome temporaneo `zsvirt-box-builder`. Controllare
   le impostazioni importate: NIC 1 **NAT**, almeno 8 vCPU, nested virtualization
   abilitata, disco OS capiente. Avviare dalla console.
3. Seguire le istruzioni upstream per il primo accesso e cambiare la password
   root. Prima di inizializzare il management, predisporre la box per Vagrant:
   NIC 1 DHCP, SSH attivo, utente `vagrant` con password scelta e sudo senza
   password. Usare `visudo` per un file dedicato, non alterare sudoers alla cieca.
4. Non salvare nella box cluster già configurati, datastore o credenziali personali.
   Spegnere ordinatamente l'appliance. Dalla macchina host, in questa cartella:

   ```bash
   vagrant package --base zsvirt-box-builder --output data/zsvirt-h84r.box
   vagrant box add --name local/zsvirt-h84r --provider virtualbox data/zsvirt-h84r.box
   ```

   Una box locale aggiunta così usa versione 0. La VM builder resta separata:
   rimuoverla solo dopo aver verificato il lab, senza cancellare dischi di altre VM.

Questa preparazione è manuale perché dipende dall'immagine distribuita da ZSvirt;
il Vagrantfile è pronto per gestirla ma non è un installer unattended dell'appliance.

## Avvio e inizializzazione

Con le altre infrastrutture spente, impostare in modo interattivo la password
vagrant scelta nella box (non salvarla in .env o file condivisi):

```bash
read -rs -p 'Password vagrant della box: ' ZS_VAGRANT_PASSWORD
export ZS_VAGRANT_PASSWORD
./scripts/up.sh
```

La NIC 2 sarà host-only **192.168.63.128/25**, MAC **08:00:27:40:01:02**.
Dalla console identificare quella NIC e configurare management
**192.168.63.139/25** usando gli strumenti ZSvirt. Non usare .129 come gateway:
è l'adattatore host-only del Bosgame e non fa routing. La default route resta
sulla NIC NAT. Gli strumenti bond/network upstream sono interattivi: selezionare
la NIC per MAC, non assumere nomi ens3/enp0s8.

Poi, dalla console root:

```bash
zstack-ctl change_ip --ip 192.168.63.139
zstack-ctl start
```

Aprire **https://192.168.63.139** dal Bosgame, completare datacenter/cluster,
aggiungere il nodo come compute e configurare datastore sul disco **100 GB**
verificato con lsblk. Creare image storage e port group, importare un'immagine
Linux e avviare una VM piccola. Non formattare il disco OS per il datastore.
Verificare AMD-V esposto e funzionamento KVM prima di insistere su errori VM.

## Stop e stato

Spegnere le VM annidate e poi `vagrant halt`. `vagrant destroy` elimina solo
le VM/dischi gestiti da questo lab; la box nella cache Vagrant resta. La box
contiene credenziali di bootstrap: non condividerla come fosse semplice codice.

Stato: fattibilità documentata, Vagrantfile staticamente validabile; import OVA,
preparazione box e avvio nested su VirtualBox **non ancora collaudati**.
