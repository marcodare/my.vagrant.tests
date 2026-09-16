# Creare una box OPNsense locale da installazione manuale

Procedura per ottenere `local/opnsense-26.1`, una box Vagrant/VirtualBox
costruita a mano dall'ISO ufficiale, pronta per il nodo `opnsense` di questo
laboratorio. È l'alternativa al bootstrap da FreeBSD usato dal `Vagrantfile`:
l'avvio diventa immediato e senza download, al prezzo di una preparazione
manuale da ripetere a ogni major release. Stesso schema della box ZSvirt.

Risultato finale:

- OPNsense 26.1 (ISO 26.1.6) su disco UFS da 10 GB dinamico;
- `em0` = **WAN** in NAT (DHCP), con SSH raggiungibile da Vagrant;
- `em1` = **LAN/MGMT** `192.168.67.10/24`, DHCP spento, GUI su `https://192.168.67.10`;
- utente `vagrant` nel gruppo `admins`, chiave insecure di Vagrant, shell
  `/bin/sh`, `sudo` senza password;
- password `root` scelta durante l'installazione, mai scritta nel repository;
- nessuna interfaccia OPT: BLUE/GREEN/DMZ si assegnano nel laboratorio.

Tutto si esegue sul Bosgame, dalla cartella del laboratorio. Il file `.box`
e l'ISO restano fuori da Git (`*.box`, `*.iso`, `data/`).

## 1. Prerequisiti

- Host preparato con `configure.host.sh` (VirtualBox 7.2, Vagrant 2.4.x).
- Circa 3 GB liberi per ISO e box; `bunzip2` e `openssl` presenti (Ubuntu li ha).
- Nessun altro laboratorio acceso: la VM builder userà la host-only `192.168.67.0/24`.

## 2. Scaricare e verificare l'ISO

Le immagini sono pubblicate su [opnsense.org/download](https://opnsense.org/download/)
e sui mirror ufficiali; `pkg.opnsense.org/releases/26.1/` elenca tutte le
26.1.x. Serve l'immagine **dvd** (ISO avviabile con installer).

```bash
mkdir -p data && cd data
base=https://pkg.opnsense.org/releases/26.1
curl -LO "$base/OPNsense-26.1.6-dvd-amd64.iso.bz2"
curl -LO "$base/OPNsense-26.1.6-dvd-amd64.iso.sig"
curl -LO "$base/OPNsense-26.1.6-checksums-amd64.sha256"
curl -LO "$base/OPNsense-26.1.pub"
```

Verifica del checksum e della firma, come da
[documentazione ufficiale](https://docs.opnsense.org/manual/install.html):

```bash
grep dvd OPNsense-26.1.6-checksums-amd64.sha256
openssl sha256 OPNsense-26.1.6-dvd-amd64.iso.bz2        # deve coincidere
bunzip2 -k OPNsense-26.1.6-dvd-amd64.iso.bz2
openssl base64 -d -in OPNsense-26.1.6-dvd-amd64.iso.sig -out /tmp/opnsense-image.sig
openssl dgst -sha256 -verify OPNsense-26.1.pub -signature /tmp/opnsense-image.sig OPNsense-26.1.6-dvd-amd64.iso.bz2
cd ..
```

L'ultimo comando deve stampare `Verified OK`. Non proseguire con checksum o
firma non validi.

## 3. Creare la VM builder in VirtualBox

Rete: NIC 1 NAT (diventerà la WAN, come nel lab), NIC 2 host-only sulla stessa
subnet del laboratorio, così la GUI si raggiunge dal Bosgame. Se non esiste
ancora un adattatore host-only con `192.168.67.1`, crearlo:

```bash
VBoxManage list hostonlyifs | grep -B3 -A6 '192.168.67.1' || {
  VBoxManage hostonlyif create            # stampa il nome, es. vboxnet1
  VBoxManage hostonlyif ipconfig vboxnetN --ip 192.168.67.1 --netmask 255.255.255.0
}
```

Sostituire `vboxnetN` con il nome ottenuto, poi:

```bash
vm=opnsense-box-builder
iso=$PWD/data/OPNsense-26.1.6-dvd-amd64.iso
VBoxManage createvm --name "$vm" --ostype FreeBSD_64 --register
VBoxManage modifyvm "$vm" --memory 2048 --cpus 2 --graphicscontroller vmsvga \
  --audio-driver none --usb off --boot1 dvd --boot2 disk
VBoxManage modifyvm "$vm" --nic1 nat --nictype1 82540EM \
  --natpf1 'ssh,tcp,127.0.0.1,2222,,22'
VBoxManage modifyvm "$vm" --nic2 hostonly --hostonlyadapter2 vboxnetN --nictype2 82540EM
VBoxManage createmedium disk --filename "$PWD/data/$vm.vdi" --size 10240 --format VDI
VBoxManage storagectl "$vm" --name SATA --add sata --controller IntelAhci --portcount 2
VBoxManage storageattach "$vm" --storagectl SATA --port 0 --device 0 --type hdd --medium "$PWD/data/$vm.vdi"
VBoxManage storageattach "$vm" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$iso"
VBoxManage startvm "$vm"
```

Il tipo NIC `82540EM` produce interfacce `em0`/`em1`, gli stessi nomi che
Vagrant crea nel laboratorio. Il port forward `2222` serve solo alla verifica
SSH del passo 7; Vagrant ne creerà uno proprio.

## 4. Installare OPNsense

Nella console VirtualBox, a boot completato dal live system:

1. Login `installer` / password `opnsense`.
2. Layout tastiera; filesystem **UFS** (più semplice, basta per il lab);
   disco `ada0`; confermare la cancellazione; swap: accettare il default.
3. **Select Root Password**: scegliere una password robusta e conservarla
   fuori dal repository.
4. Completare e riavviare. Alla schermata del bootloader spegnere la VM,
   togliere l'ISO e riaccendere:

   ```bash
   VBoxManage controlvm "$vm" poweroff
   VBoxManage storageattach "$vm" --storagectl SATA --port 1 --device 0 --type dvddrive --medium emptydrive
   VBoxManage startvm "$vm"
   ```

## 5. Assegnare le interfacce dalla console

Il default OPNsense è LAN=`em0`, WAN=`em1`: va invertito, perché nel lab la NAT
(`em0`) è la WAN. Login `root` nella console, poi menu:

1. Opzione **1) Assign interfaces**: nessuna VLAN; WAN = `em0`; LAN = `em1`;
   confermare.
2. Opzione **2) Set interface IP address** → LAN: IPv4 statico
   `192.168.67.10`, prefisso `24`, nessun gateway, IPv6 no, **DHCP server no**,
   HTTPS sì.
3. La WAN resta in DHCP: prende `10.0.2.15` dalla NAT VirtualBox e la default
   route. Verificare con l'opzione 8 (shell): `ifconfig em0`, `ping 1.1.1.1`.

## 6. Configurare dalla GUI

Aprire `https://192.168.67.10` dal Bosgame (certificato autofirmato), login
`root`. Il wizard può essere completato con: hostname `opnsense`, dominio
`lab.internal`, fuso `Etc/UTC`, DNS lasciati dal DHCP; alla pagina WAN
**deselezionare** *Block private networks* e *Block bogon networks* (la NAT è
`10.0.2.0/24`; con il blocco attivo Vagrant non entrerebbe mai). Se il wizard
è già stato saltato, le stesse caselle sono in *Interfaces: WAN*.

Poi, nell'ordine:

1. **System: Settings: Administration**
   - *Secure Shell*: Enable Secure Shell; *Permit password login* no;
     *Listen Interfaces* vuoto (tutte); porta 22.
   - *Sudo*: **No password**, gruppo `admins`.
   - Salvare.
2. **System: Access: Users** → aggiungere:
   - Username `vagrant`, password qualsiasi (non verrà usata: il login è
     solo a chiave), *Login shell* `/bin/sh`, gruppo `admins`.
   - *Authorized keys*: incollare la chiave pubblica insecure di Vagrant,
     presente sul Bosgame in
     `/opt/vagrant/embedded/gems/gems/vagrant-2.4.9/keys/vagrant.pub.ed25519`
     (o `vagrant.pub` RSA; l'originale è nel
     [repository Vagrant](https://github.com/hashicorp/vagrant/tree/main/keys)).
     Vagrant la sostituisce con una chiave propria al primo `vagrant up`.
   - Salvare.
3. **Firewall: Rules: WAN** → aggiungere: azione *Pass*, interfaccia WAN,
   direzione in, IPv4, protocollo TCP, sorgente any, destinazione *WAN
   address*, porta 22, descrizione `Vagrant SSH`. Applicare le modifiche.
4. **Firewall: Rules: LAN**: verificare che esista la regola anti-lockout e la
   `Default allow LAN to any`.
5. **System: Firmware: Plugins** → installare `os-virtualbox` (guest
   additions FreeBSD): permette a Vagrant uno spegnimento ACPI pulito.
   Facoltativo: *System: Firmware: Status* → aggiornare alla 26.1.x corrente.
6. **System: Configuration: Backups** → scaricare una copia della
   `config.xml` in `data/` (fuori Git): è la fotografia della box.

## 7. Verificare l'accesso Vagrant prima di impacchettare

Dal Bosgame, con la chiave privata insecure (copiarla perché ssh esige
permessi 600):

```bash
cp /opt/vagrant/embedded/gems/gems/vagrant-2.4.9/keys/vagrant.key.ed25519 /tmp/vagrant.key
chmod 600 /tmp/vagrant.key
ssh -i /tmp/vagrant.key -p 2222 -o StrictHostKeyChecking=no vagrant@127.0.0.1 'uname -a; sudo -n id'
rm /tmp/vagrant.key
```

Attesi: `FreeBSD ... OPNsense` e `uid=0(root)`. Se il login fallisce controllare
in ordine: regola WAN applicata, *Block private networks* disattivato, SSH
abilitato, chiave incollata senza a capo. Se `sudo` chiede la password,
ricontrollare *Sudo: No password* e il gruppo `admins` dell'utente.

## 8. Spegnere e impacchettare

Dalla console OPNsense opzione **6) Power off system**, oppure
`VBoxManage controlvm "$vm" acpipowerbutton`. A VM spenta:

```bash
vagrant package --base "$vm" --output data/opnsense-26.1.box
vagrant box add --name local/opnsense-26.1 --provider virtualbox data/opnsense-26.1.box
vagrant box list | grep opnsense
```

La box aggiunta da file ha versione `0`. La VM builder può restare
registrata (spenta) per futuri aggiornamenti: per rifare la box basta
accenderla, aggiornare, spegnere e ripetere `package` + `box add --force`.
Il `.box` include il disco così com'è: mantenere il builder pulito (nessun
log o segreto in più oltre alla password root).

## 9. Prova rapida della box

In una cartella temporanea fuori dal repository:

```ruby
Vagrant.configure('2') do |config|
  config.vm.box = 'local/opnsense-26.1'
  config.ssh.shell = '/bin/sh'
  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.vm.network 'private_network', ip: '192.168.67.10', auto_config: false
end
```

```bash
vagrant up && vagrant ssh -c 'sudo -n opnsense-version' && vagrant halt && vagrant destroy -f
```

`config.ssh.shell = '/bin/sh'` è obbligatorio: OPNsense non ha bash. Il
`private_network` è necessario perché la LAN della box è su `em1`.

## 10. Uso nel laboratorio

Il `Vagrantfile` del lab oggi parte da `bento/freebsd-14.3` e usa il bootstrap.
Per usare invece la box locale servono tre adattamenti, non ancora applicati:

1. in `lab.json`, nodo `opnsense`: `"box": "local/opnsense-26.1"`,
   `"box_version": "0"`;
2. in `scripts/lab_config.py`, ammettere quella box per il ruolo `opnsense`;
3. `scripts/provision/opnsense.sh` salta già il bootstrap se OPNsense è
   presente e riscrive `config.xml` con interfacce, utente Vagrant e regole
   del lab, riutilizzando l'hash root esistente: verificare che la chiave in
   `/home/vagrant/.ssh/authorized_keys` sia quella attesa dopo il primo boot.

Nel percorso basic (`Vagrant.start`) la box locale è invece utilizzabile
subito con la stessa modifica a `lab.json`: si parte da un OPNsense già
installato e si prosegue da STEPS.md, passo 3 (assegnazione OPT1–OPT3).

Fonti: [download OPNsense](https://opnsense.org/download/),
[installazione e verifica immagini](https://docs.opnsense.org/manual/install.html),
[chiavi insecure Vagrant](https://github.com/hashicorp/vagrant/tree/main/keys),
[vagrant package](https://developer.hashicorp.com/vagrant/docs/cli/package),
[VBoxManage](https://www.virtualbox.org/manual/ch08.html).
