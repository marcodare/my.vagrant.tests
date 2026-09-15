# openstack_3nodes_simple

Per studiare tutto a mano usare `Vagrant.start` e seguire [STEPS.md](STEPS.md).
Il `Vagrantfile` mantiene il percorso assistito già disponibile.

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito
VAGRANT_VAGRANTFILE=Vagrant.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh controller
```

Nel percorso basic continuare con STEPS.md. Usare la variabile anche per
`status`, `halt` e `destroy`; non alternare i due file sulle stesse VM.

OpenStack **2025.2 con Kolla Ansible 21.3.0**, su tre VM Ubuntu 24.04:
un controller/network e due compute KVM. Configurazione semplice, **non HA**.
Ogni file del laboratorio è locale; non serve una cartella shared.

| Nodo | Management | RAM | vCPU | Disco OS |
| --- | --- | --- | --- | --- |
| controller | 192.168.63.11/25 | 16 GiB | 6 | 80 GB |
| compute1 | 192.168.63.21/25 | 16 GiB | 6 | 80 GB |
| compute2 | 192.168.63.22/25 | 16 GiB | 6 | 80 GB |

Totale 48 GiB. API/Horizon VIP **192.168.63.5**. La metà superiore del /24 è
riservata al lab ZSvirt; VirtualBox crea reti host-only /25 distinte.

NIC 1 NAT: Vagrant/download. NIC 2 **enpmgmt**: management/API/tunnel VXLAN.
NIC 3 **enpext**: rete provider interna `openstack_3nodes_simple-external`,
senza IP sul sistema operativo; sarà collegata a br-ex da Neutron/OVS.
Il segmento provider di studio è 10.63.1.0/24 e non ha router verso Internet.
Le VM possono comunicare nel laboratorio; per un'uscita esterna aggiungere
successivamente un router virtuale, senza dare un gateway inesistente alla subnet.

## 1. Preparazione nodi

Host già configurato con VirtualBox/Vagrant; altri lab spenti:

```bash
./scripts/up.sh
vagrant ssh controller
```

Provisioning crea reti, verifica nested KVM sui compute e installa sul controller
la venv `/opt/kolla-venv`. Non installa libvirt sull'host guest: lo gestirà Kolla
nei container. `config/globals.yml` e `config/multinode` vengono copiati in
`/home/vagrant/infra-kolla`, globals anche in `/etc/kolla`.
L'inventory contiene i gruppi servizio upstream di stable/2025.2, con i nodi
iniziali adattati a questo lab. Il deploy non usa le dipendenze Python dell'host.

## 2. SSH dal controller

Kolla deve poter accedere a **controller, compute1 e compute2** come vagrant con
sudo. Da controller creare una chiave dedicata al solo lab con `ssh-keygen`.
Installarne la parte pubblica nell'authorized_keys dell'utente vagrant dei tre
nodi, anche del controller. Usare le sessioni `vagrant ssh` per questa operazione;
non copiare la chiave SSH dell'host o credenziali nel repository. Verificare e
accettare i fingerprint al primo collegamento:

```bash
ssh vagrant@192.168.63.11 sudo true
ssh vagrant@192.168.63.21 sudo true
ssh vagrant@192.168.63.22 sudo true
```

## 3. Deploy guidato

Sul controller come vagrant:

```bash
source /opt/kolla-venv/bin/activate
cd ~/infra-kolla
kolla-ansible install-deps
kolla-genpwd
ansible -i multinode all -m ping
kolla-ansible bootstrap-servers -i multinode
kolla-ansible prechecks -i multinode
kolla-ansible deploy -i multinode
kolla-ansible post-deploy -i multinode
```

Generare le password solo durante l'installazione iniziale. Non rilanciare
`kolla-genpwd` dopo aver popolato i servizi. Custodire passwords.yml e gli
openrc/clouds.yaml generati in `/etc/kolla`: sono segreti e non vanno nel Git.
Se i precheck falliscono, correggere la causa prima del deploy (spazio reale
filesystem, NIC enpext senza IP, KVM disponibile, container runtime, SSH/sudo).
Le immagini container seguono il tag 2025.2: il patch level può cambiare.

## 4. Prima VM e reti

Accedere a Horizon su **http://192.168.63.5** con le credenziali generate.
Usare l'openrc prodotto da post-deploy nel proprio ambiente di amministrazione;
verificare `openstack compute service list` e `openstack hypervisor list`:
due compute devono essere Up. Glance usa storage del controller; Cinder è
volutamente disabilitato, i dischi delle istanze sono locali/effimeri.

Con credenziali amministrative caricate, creare la rete provider isolata:

```bash
openstack network create --external --provider-network-type flat --provider-physical-network physnet1 lab-external
openstack subnet create --network lab-external --subnet-range 10.63.1.0/24 --no-dhcp --no-gateway --allocation-pool start=10.63.1.100,end=10.63.1.199 lab-external-subnet
openstack network create tenant
openstack subnet create --network tenant --subnet-range 172.20.10.0/24 tenant-subnet
openstack router create tenant-router
openstack router add subnet tenant-router tenant-subnet
openstack router set --external-gateway lab-external tenant-router
```

Caricare un'immagine cloud Linux verificata in Glance e creare flavor piccolo
(2 vCPU, 2 GiB, 10 GB). Creare una VM per compute sulla rete tenant, aprire
ICMP/SSH nel security group e verificare comunicazione fra nodi dalla console.
Gli eventuali floating IP sono sulla provider **interna**: non sono raggiungibili
dal Bosgame senza un router/una rotta aggiunti esplicitamente. Per il primo lab
usare la console Horizon. Nessuna connettività Internet delle istanze è promessa.

## Esercizi e arresto

Esplorare progetti, utenti, flavor, immagini, security group, DHCP/VXLAN e
scheduling. Il singolo controller è un punto di guasto; non usare questo lab
come prova di HA o live migration con storage condiviso. Spegnere le istanze,
poi `vagrant halt`; `vagrant up` riprende i nodi e i container persistenti.
`vagrant destroy` elimina database, immagini e istanze del lab.

Stato: preparazione automatizzata e runbook di deploy; collaudo reale da eseguire.
Fonti: [quickstart Kolla](https://docs.openstack.org/kolla-ansible/2025.2/user/quickstart.html),
[inventory upstream](https://github.com/openstack/kolla-ansible/blob/stable/2025.2/ansible/inventory/multinode).
