# Percorso manuale: quattro distribuzioni Linux

Questa procedura parte da quattro sistemi operativi puliti e costruisce a mano
la configurazione che il `Vagrantfile` assistito applica automaticamente. Lo
scopo non è soltanto ottenere quattro nodi raggiungibili, ma capire quali parti
sono comuni a Linux e quali cambiano fra Ubuntu e Rocky Linux.

## Risultato atteso

Al termine ogni VM avrà:

- un hostname stabile e coerente con la topologia;
- una NIC NAT con DHCP e default route, usata per SSH e accesso ai repository;
- una NIC host-only con IP statico, usata esclusivamente dal laboratorio;
- risoluzione locale dei nomi tramite `/etc/hosts`;
- sincronizzazione dell'orologio con chrony;
- strumenti di diagnosi equivalenti sulle quattro distribuzioni.

| Nodo | Sistema | IP del lab | MAC della NIC del lab |
| --- | --- | --- | --- |
| `ubuntu24` | Ubuntu 24.04 | `192.168.66.11/24` | `08:00:27:48:01:02` |
| `rocky9` | Rocky Linux 9 | `192.168.66.12/24` | `08:00:27:48:02:02` |
| `ubuntu26` | Ubuntu 26.04 | `192.168.66.13/24` | `08:00:27:48:03:02` |
| `rocky10` | Rocky Linux 10 | `192.168.66.14/24` | `08:00:27:48:04:02` |

La rete `192.168.66.0/24` non ha un gateway: serve soltanto per il traffico fra
i nodi e fra i nodi e il Bosgame. La default route deve rimanere sulla NIC NAT;
in questo modo la rete didattica non modifica il percorso usato per scaricare i
pacchetti e non diventa accidentalmente una seconda uscita verso Internet.

## Prerequisiti e cautele

Sul Bosgame devono essere già installati VirtualBox e Vagrant e deve essere
consentito il range host-only del progetto in `/etc/vbox/networks.conf`, come
descritto nel README principale. Tenere spente le altre infrastrutture del
repository.

Questa guida modifica rete, hostname e pacchetti **dentro le VM**, mai
sull'host. Prima di modificare una VM generica o bare metal assicurarsi di avere
accesso alla console: un MAC o un nome di interfaccia errato può interrompere
la connettività. Su hardware reale sostituire indirizzi, MAC e nomi secondo la
propria topologia e verificare che `192.168.66.0/24` non si sovrapponga a LAN o
VPN.

Rocky Linux 10 richiede una CPU x86-64-v3. Il Ryzen AI Max+ 395 previsto dal
laboratorio soddisfa il requisito; host più vecchi potrebbero non avviare la VM.

## 1. Creare le VM senza provisioning

Dalla cartella `linux_4nodes`:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
```

`Vagrantfile.start` crea soltanto VM, NIC e dischi. L'opzione
`auto_config: false` fa creare a VirtualBox la seconda scheda, ma impedisce a
Vagrant di assegnarle l'IP nel guest. Questo lascia visibile ogni passaggio che
nei laboratori reali va compreso e verificato.

Usare `VAGRANT_VAGRANTFILE=Vagrantfile.start` anche per tutti i successivi
comandi `ssh`, `halt`, `reload` e `destroy`. Senza la variabile Vagrant usa il
percorso assistito e considera le macchine come un ambiente differente.

Accedere al primo nodo:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh ubuntu24
```

Ripetere poi i passi pertinenti su `rocky9`, `ubuntu26` e `rocky10`.

## 2. Fotografare lo stato iniziale

Prima di cambiare qualcosa, raccogliere le informazioni che permetteranno di
capire l'effetto di ogni comando:

```bash
cat /etc/os-release
hostnamectl
ip -br link
ip -br address
ip route
lsblk
df -hT
```

Ci si aspetta di vedere una NIC NAT già configurata via DHCP, con la default
route, e una seconda NIC attiva ma priva di indirizzo IPv4. `lsblk` e `df`
servono a distinguere la dimensione del disco virtuale da quella effettivamente
usata da partizione e filesystem: Vagrant porta il supporto a 80 GB, ma la box
potrebbe non espandere automaticamente il filesystem.

Individuare la NIC del lab dal MAC, senza assumere che si chiami `enp0s8`:

```bash
ip -o link
```

I nomi prevedibili dipendono dalla distribuzione e dalla versione. Il MAC è
invece fissato nel file Vagrant e identifica la scheda in modo non ambiguo.
Verificare che corrisponda alla tabella precedente. Dal Bosgame si può fare un
controllo indipendente con:

```bash
VBoxManage showvminfo linux_4nodes-ubuntu24-start
```

## 3. Impostare hostname e risoluzione locale

Su ogni nodo impostare il nome indicato nella tabella, per esempio:

```bash
sudo hostnamectl set-hostname ubuntu24
hostnamectl --static
```

Usare rispettivamente `rocky9`, `ubuntu26` e `rocky10` sugli altri nodi.
L'hostname identifica il sistema nei prompt, nei log e negli strumenti di
amministrazione; mantenerlo coerente con Vagrant evita di confondere una VM con
un'altra durante i test.

Su tutte e quattro le VM aggiungere a `/etc/hosts`:

```text
# BEGIN LINUX LAB
192.168.66.11 ubuntu24
192.168.66.12 rocky9
192.168.66.13 ubuntu26
192.168.66.14 rocky10
# END LINUX LAB
```

`/etc/hosts` offre una risoluzione dei nomi deterministica senza introdurre un
server DNS nel laboratorio. Non sostituisce il DNS Internet: aggiunge soltanto
questi quattro nomi locali. Verificare sintassi e risultato:

```bash
getent hosts ubuntu24 rocky9 ubuntu26 rocky10
```

Prima di configurare gli IP è normale che i nomi vengano risolti ma non siano
ancora raggiungibili.

## 4. Configurare la NIC del lab su Ubuntu

Eseguire questa sezione su `ubuntu24` e `ubuntu26`, usando IP e MAC della
rispettiva riga della tabella. Su `ubuntu24`, creare con `sudoedit` il file
`/etc/netplan/60-infra-lab.yaml`:

```yaml
network:
  version: 2
  ethernets:
    enplab:
      match:
        macaddress: 08:00:27:48:01:02
      set-name: enplab
      addresses:
        - 192.168.66.11/24
      dhcp4: false
```

Su `ubuntu26` cambiare MAC in `08:00:27:48:03:02` e indirizzo in
`192.168.66.13/24`. Proteggere il file e validarlo prima di applicarlo:

```bash
sudo chmod 0600 /etc/netplan/60-infra-lab.yaml
sudo netplan generate
sudo netplan try
sudo netplan apply
```

Il `match` sul MAC evita di legare la configurazione a un nome assegnato da
udev; `set-name` fornisce poi il nome leggibile `enplab`. Non si definiscono
gateway, route di default o DNS su questa interfaccia. `netplan generate`
intercetta gli errori di sintassi; `netplan try` offre un rollback temporizzato,
utile soprattutto quando si lavora da remoto. La sessione Vagrant usa comunque
la NIC NAT, che questa configurazione non modifica.

Verificare:

```bash
ip -br address show enplab
ip route
```

Deve comparire l'IP statico assegnato a `enplab`, mentre la riga `default via`
deve continuare a usare la NIC NAT.

## 5. Configurare la NIC del lab su Rocky Linux

Rocky usa NetworkManager. Su `rocky9` creare un profilo associato al MAC della
seconda NIC:

```bash
sudo nmcli connection add type ethernet con-name lab \
  802-3-ethernet.mac-address 08:00:27:48:02:02 \
  ipv4.method manual ipv4.addresses 192.168.66.12/24 \
  ipv4.never-default yes ipv6.method disabled \
  connection.autoconnect yes
sudo nmcli connection up lab
```

Su `rocky10` usare MAC `08:00:27:48:04:02` e IP `192.168.66.14/24`.
`ipv4.never-default yes` esprime esplicitamente che questo profilo non deve mai
fornire la default route. L'associazione al MAC impedisce che il profilo venga
applicato per errore alla NIC NAT. NetworkManager è obbligatorio su Rocky 10:
i vecchi script `ifcfg` non sono più supportati.

Se il profilo `lab` esiste già dopo un tentativo precedente, ispezionarlo o
rimuoverlo prima di ricrearlo:

```bash
nmcli connection show lab
sudo nmcli connection delete lab
```

Verificare la configurazione attiva:

```bash
nmcli device status
nmcli connection show --active
ip -br address
ip route
```

Anche qui deve esistere una sola default route, tramite la NIC NAT.

## 6. Installare strumenti equivalenti

Sulle due VM Ubuntu:

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl chrony iproute2 iputils-ping traceroute tcpdump \
  iperf3 netcat-openbsd dnsutils rsync vim tmux
sudo systemctl enable --now chrony
```

Sulle due VM Rocky:

```bash
sudo dnf install -y \
  ca-certificates curl chrony iproute iputils traceroute tcpdump iperf3 \
  nmap-ncat bind-utils rsync vim-enhanced tmux
sudo systemctl enable --now chronyd
```

I nomi dei pacchetti cambiano, ma le capacità installate sono intenzionalmente
equivalenti: diagnostica IP, ICMP, route, cattura pacchetti, test di throughput,
client TCP/UDP, query DNS e copia di file. Questo rende il confronto fra le due
famiglie significativo senza nascondere le differenze dei package manager.

chrony mantiene gli orologi allineati. La sincronizzazione è essenziale per
confrontare log, diagnosticare eventi distribuiti e usare protocolli sensibili
al tempo. Il pacchetto si chiama `chrony` su entrambe le famiglie, ma l'unità
systemd è `chrony` su Ubuntu e `chronyd` su Rocky.

Verificare su ogni nodo:

```bash
timedatectl
chronyc tracking
chronyc sources -v
```

Una sorgente può richiedere alcuni minuti prima di essere selezionata. La NIC
NAT deve avere connettività Internet perché chrony e i repository siano
raggiungibili.

## 7. Verificare rete e risoluzione dei nomi

Da ogni nodo eseguire ping verso gli altri tre, prima per IP e poi per nome. Da
`ubuntu24`, per esempio:

```bash
ping -c 3 192.168.66.12
ping -c 3 rocky9
ping -c 3 ubuntu26
ping -c 3 rocky10
ip route get 192.168.66.12
```

`ip route get` deve mostrare che il traffico verso `192.168.66.0/24` esce dalla
NIC del lab, non dalla NAT. Se il ping per IP funziona ma quello per nome no, il
problema è in `/etc/hosts`; se non funziona neppure per IP, controllare MAC,
prefisso `/24`, stato della NIC e firewall.

Controllare inoltre porte in ascolto e policy di sicurezza:

```bash
ss -tulpen
```

Su Ubuntu:

```bash
sudo ufw status verbose
sudo aa-status
```

Su Rocky:

```bash
sudo firewall-cmd --state
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all
getenforce
```

Questi comandi distinguono tre piani diversi: un processo in ascolto, il
firewall che consente o blocca il traffico e il controllo MAC di AppArmor o
SELinux. Un servizio può quindi essere attivo ma non raggiungibile per ragioni
diverse.

## 8. Fault test del firewall con iperf3

Sul nodo `rocky9` avviare il server in primo piano:

```bash
iperf3 -s
```

Da `ubuntu24`, in un altro terminale:

```bash
iperf3 -c rocky9
```

Con `firewalld` attivo la porta TCP 5201 dovrebbe essere bloccata. Se il test
riesce già, controllare zona e regole: la box potrebbe avere una configurazione
diversa da quella attesa.

Su `rocky9` individuare la zona associata al profilo `lab`, quindi aprire la
porta soltanto nella configurazione runtime:

```bash
nmcli -g GENERAL.DEVICES connection show lab
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --zone=public --add-port=5201/tcp
sudo firewall-cmd --zone=public --query-port=5201/tcp
```

Se l'interfaccia `lab` appartiene a una zona diversa da `public`, usare quella
zona nei comandi. Ripetere `iperf3 -c rocky9`: ora deve mostrare il throughput.
La modifica runtime è intenzionale, perché consente di sperimentare senza
rendere permanente una regola didattica. Rimuoverla al termine:

```bash
sudo firewall-cmd --zone=public --remove-port=5201/tcp
```

Per confronto, `--permanent` scriverebbe la regola persistente, ma non la
renderebbe immediatamente attiva senza un reload o un'aggiunta anche runtime.

## 9. Fault test della sincronizzazione temporale

Su un nodo Ubuntu osservare prima lo stato e poi fermare chrony:

```bash
chronyc tracking
sudo systemctl stop chrony
systemctl is-active chrony
timedatectl
```

Su Rocky sostituire `chrony` con `chronyd`. Fermare il demone non produce
immediatamente una grande deriva: dimostra invece che il nodo non sta più
correggendo il proprio clock. Lasciarlo fermo a lungo renderebbe progressivamente
meno affidabili timestamp e correlazione dei log. Ripristinare il servizio e
controllare la risincronizzazione:

```bash
sudo systemctl start chrony
chronyc sources -v
chronyc tracking
```

Su Rocky usare `sudo systemctl start chronyd`.

## 10. Fault test di un nodo

Dal Bosgame spegnere soltanto `rocky10`:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt rocky10
```

Verificare che `ubuntu24`, `rocky9` e `ubuntu26` continuino a comunicare. Il
test mostra che questa è una rete di nodi indipendenti: non esistono quorum,
VIP o servizi cluster che rendano gli altri dipendenti da `rocky10`.

Riavviare il nodo e verificare la persistenza di hostname, profilo di rete e
servizi:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up rocky10
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh rocky10
hostnamectl --static
nmcli connection show --active
systemctl is-active chronyd
```

## 11. Esercizi di confronto

- Confrontare `apt` e `dnf`: ricerca, installazione, aggiornamenti e cronologia.
- Confrontare `systemd-analyze` e `systemctl --failed` sulle quattro release.
- Osservare un flusso `iperf3` con `sudo tcpdump -ni enplab port 5201` su Ubuntu.
  Su Rocky ricavare prima il vero nome della NIC con
  `nmcli -g GENERAL.DEVICES connection show lab`: `lab` è il nome del profilo,
  non necessariamente quello dell'interfaccia.
- Confrontare `nc -l` su Ubuntu con `ncat -l` su Rocky e osservare le porte con
  `ss -tulpen`.
- Esaminare AppArmor con `aa-status` e SELinux con `getenforce`, `ls -Z` e, se
  disponibile, `ausearch -m AVC`.
- Creare chiavi SSH dedicate al laboratorio, copiarle soltanto fra questi nodi
  e provare `rsync` preservando permessi e timestamp.
- Registrare in `data/` le differenze fra kernel, systemd, OpenSSL e Python con
  `uname -r`, `systemd --version`, `openssl version` e `python3 --version`.

## Arresto e reset

Per conservare il lavoro:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt
```

Per eliminare definitivamente le quattro VM e ripartire da sistemi puliti:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```

`destroy` è distruttivo e richiede conferma. Non alternare questo file con il
`Vagrantfile` assistito sulle stesse istanze. Per cambiare percorso, salvare gli
appunti, distruggere esplicitamente le VM con la stessa variabile usata per
crearle e avviare poi l'altro percorso.

## Riferimenti

- [Netplan: identificare una scheda tramite MAC](https://netplan.readthedocs.io/en/stable/matching-interface-by-mac-address/)
- [NetworkManager: proprietà utilizzabili con nmcli](https://www.networkmanager.dev/docs/api/latest/nm-settings-nmcli.html)
- [Rocky Linux 10: NetworkManager sostituisce i vecchi network scripts](https://docs.rockylinux.org/latest/releases/release_notes/10_0/)
- [firewalld: configurazione runtime e permanente](https://firewalld.org/documentation/configuration/runtime-versus-permanent.html)
- [firewalld: apertura di porte e servizi](https://firewalld.org/documentation/howto/open-a-port-or-service.html)
- [Catalogo delle box Bento](https://portal.cloud.hashicorp.com/vagrant/discover/bento)
