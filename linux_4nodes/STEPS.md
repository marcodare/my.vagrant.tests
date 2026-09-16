# Percorso manuale: quattro distribuzioni Linux

## Uso su Vagrant, VM generiche o bare metal

`Vagrant.start` è solo il punto di partenza VirtualBox. Fuori da Vagrant usare
quattro sistemi puliti amd64: Ubuntu 24.04, Rocky Linux 9, Ubuntu 26.04 e Rocky
Linux 10, con una NIC comune sullo stesso segmento e una seconda NIC o route
verso Internet per i repository. Sostituire IP e nomi NIC nei passi seguenti,
mantenere hostname coerenti e NTP attivo. Prima di modificare la rete conservare
l'accesso console. Rocky 10 richiede una CPU x86-64-v3.

1. Avviare `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up` e accedere con
   `VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh ubuntu24`. Identificare la NIC
   del lab con `ip -br link` e il MAC `08:00:27:48:0N:02` mostrato da
   `VBoxManage showvminfo`; la NIC NAT conserva la default route.
2. Su ogni nodo impostare hostname e `/etc/hosts` con i quattro indirizzi:
   `192.168.66.11 ubuntu24`, `.12 rocky9`, `.13 ubuntu26`, `.14 rocky10`.
3. Assegnare l'IP alla NIC del lab, `/24` e senza gateway. Su Ubuntu creare
   `/etc/netplan/60-infra-lab.yaml` con `match: {macaddress: ...}` e
   `addresses`, poi `netplan apply`. Su Rocky usare
   `nmcli connection add type ethernet con-name lab 802-3-ethernet.mac-address <MAC> ipv4.method manual ipv4.addresses <IP>/24 ipv4.never-default yes`
   e `nmcli connection up lab`.
4. Installare e abilitare NTP: `chrony` su Ubuntu, `chronyd` su Rocky. Installare
   `tcpdump`, `iperf3`, `traceroute` e un client DNS (`dnsutils` / `bind-utils`).
5. Verificare da ogni nodo `ping` e risoluzione degli altri tre nomi, `ss -tlnp`
   e lo stato del firewall: `ufw status` su Ubuntu, `firewall-cmd --state` e
   `firewall-cmd --list-all` su Rocky.
6. Fault test: aprire `iperf3 -s` su rocky9 e collegarsi da ubuntu24; osservare
   il blocco di `firewalld`, poi `firewall-cmd --add-port=5201/tcp` e ripetere.
   Fermare `chronyd` su un nodo e controllare la deriva con `chronyc tracking`.
   Spegnere `rocky10` con `vagrant halt rocky10` e verificare che gli altri
   nodi restino raggiungibili fra loro.
7. Esercizi: confronto `apt`/`dnf`, `systemd-analyze`, AppArmor/SELinux, scambio
   chiavi SSH e `rsync` fra distribuzioni; annotare le differenze fra 24.04/9 e
   26.04/10 in `data/`.

Non alternare questo file con il `Vagrantfile` automatico sulla stessa istanza:
prima occorre distruggere esplicitamente il lab, perdendo i suoi dati.

Fonti: [box Bento](https://portal.cloud.hashicorp.com/vagrant/discover/bento),
[netplan](https://netplan.readthedocs.io/en/stable/),
[NetworkManager su Rocky](https://docs.rockylinux.org/guides/network/basic_network_configuration/),
[firewalld](https://firewalld.org/documentation/).
