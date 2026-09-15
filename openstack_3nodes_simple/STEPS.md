# Percorso manuale: OpenStack con Kolla-Ansible

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant preparare tre Ubuntu 24.04 puliti: controller/network e due
compute con virtualizzazione hardware. Ogni nodo richiede management e una NIC
provider dedicata; adattare IP, nomi interfacce e VIP nei file `config/`.
Predisporre DNS, NTP, SSH con sudo senza prompt dal deploy node e accesso ai
registry. La rete provider deve essere progettata rispetto allo switch reale.

1. Avviare con `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. Configurare
   management `192.168.63.11/.21/.22/25`; lasciare senza IP la NIC provider
   collegata a `10.63.1.0/24`. Impostare hostname, `/etc/hosts` e NTP.
2. Verificare nested KVM sui compute. Sul controller creare un venv, installare
   Kolla-Ansible 21.3.0 e client OpenStack, copiare esempi in `/etc/kolla` e
   preparare inventario multinode. I file in `config/` mostrano i valori attesi.
3. Generare password localmente, configurare OpenStack 2025.2, interfacce
   `enpmgmt`/`enpext`, VIP `192.168.63.5`, Open vSwitch e KVM.
4. Eseguire in sequenza `kolla-ansible install-deps`, `bootstrap-servers`,
   `prechecks`, `deploy` e `post-deploy`, risolvendo ogni errore prima di avanzare.
5. Creare image, flavor, rete provider, security group e istanza. Verificare
   console, scheduling e migrazione consentita dallo storage. Il [README](README.md)
   contiene i comandi completi e i limiti della rete provider isolata.
