# Percorso manuale: OPNsense e quattro Debian

## Uso su Vagrant, VM generiche o bare metal

`Vagrant.start` è solo il punto di partenza VirtualBox. Fuori da Vagrant usare
quattro Debian 13 amd64 puliti e una macchina con cinque NIC per OPNsense:
uplink (WAN), management e tre segmenti interni realizzati con switch, VLAN o
reti virtuali separate. Su bare metal installare OPNsense dall'ISO ufficiale
invece del bootstrap da FreeBSD; il risultato è lo stesso. Sostituire IP e
nomi NIC nei passi seguenti mantenendo la separazione dei segmenti e un solo
punto di transito fra loro: il firewall. Conservare accesso console prima di
modificare la rete.

1. Avviare `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. I MAC sono
   `08:00:27:43:NN:SS` con NN indice del nodo (01–05) e SS numero NIC
   (02 management, 03–05 segmenti); `VBoxManage showvminfo` li elenca.
2. **OPNsense.** Entrare con `VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh
   opnsense`, poi `sudo -i` e:

   ```sh
   fetch -o opnsense-bootstrap.sh https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in
   sh ./opnsense-bootstrap.sh -r 26.1
   ```

   Al riavvio la VM è OPNsense con `root`/password di default e SSH spento:
   usare la console VirtualBox. Dal menu assegnare le interfacce (opzione 1):
   WAN `em0` (NAT), LAN `em1` (host-only), OPT1 `em2`, OPT2 `em3`, OPT3 `em4`.
   Con l'opzione 2 dare alla LAN `192.168.67.10/24` senza gateway né DHCP.
3. Dalla GUI `https://192.168.67.10` (Bosgame) completare il wizard cambiando
   la password. In *Interfaces* abilitare OPT1–OPT3 come BLUE `10.67.1.1/24`,
   GREEN `10.67.2.1/24`, DMZ `10.67.3.1/24`. In *Interfaces: WAN* disattivare
   il blocco delle reti private, altrimenti la NAT 10.0.2.0/24 è scartata.
   In *System: Settings: Administration* abilitare SSH e, se serve `vagrant
   ssh`, aggiungere una regola WAN che consenta TCP 22 verso l'indirizzo WAN.
4. **Regole iniziali.** Su BLUE e GREEN una regola pass "rete → any"; su DMZ
   nessuna regola. Verificare in *Firewall: Rules* che la LAN mantenga la
   regola anti-lockout.
5. **Debian.** Su ogni nodo impostare hostname, `/etc/hosts` con gli indirizzi
   dei segmenti (`10.67.1.11 blue1`, `10.67.1.12 blue2`, `10.67.2.13 green1`,
   `10.67.3.14 dmz1`, `192.168.67.10 opnsense`), IP di management
   `192.168.67.1x/24` e IP del segmento `10.67.S.1x/24` in
   `/etc/network/interfaces.d/`, con `up ip route replace 10.67.T.0/24 via
   10.67.S.1` per gli altri due segmenti. Installare `chrony`, `tcpdump`,
   `iperf3`, `traceroute`, `mtr-tiny`, `dnsutils`.
6. **Verifiche.** `traceroute 10.67.2.13` da blue1 deve mostrare `10.67.1.1`
   come primo salto. `ping` da dmz1 verso blue1 deve fallire; da blue1 verso
   dmz1 deve riuscire. Sul firewall `pfctl -ss` mostra gli stati e
   `tcpdump -ni em4` il traffico in DMZ. In *Firewall: Log Files: Live View*
   compaiono i blocchi.
7. **Fault test.** Aggiungere una regola di blocco ICMP BLUE→GREEN e osservare
   `ping` e log; rimuoverla. Riavviare OPNsense durante un `iperf3` fra blue1
   e green1 e misurare la ripresa. Cambiare la default route di un Debian su
   OPNsense (`ip route replace default via 10.67.1.1`) e verificare uscita
   Internet via NAT del firewall e DNS con Unbound; ripristinare con `ifdown`
   e `ifup` della NIC NAT. Spegnere il firewall e confermare che i segmenti
   restano isolati fra loro mentre il management continua a funzionare.
8. Esercizi: port forward WAN→DMZ, alias e schedule, NAT reflection, IDS
   Suricata su un'interfaccia, backup e ripristino della `config.xml`.

Non alternare questo file con il `Vagrantfile` automatico sulla stessa istanza:
prima occorre distruggere esplicitamente il lab, perdendo i suoi dati.

Fonti: [opnsense-bootstrap](https://github.com/opnsense/update),
[installazione OPNsense](https://docs.opnsense.org/manual/install.html),
[assegnazione interfacce](https://docs.opnsense.org/manual/interfaces.html),
[regole firewall](https://docs.opnsense.org/manual/firewall.html),
[vagrant-opnsense di punkt.de](https://github.com/punktDe/vagrant-opnsense).
