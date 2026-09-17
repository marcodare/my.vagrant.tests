# Configurazione manuale Kubernetes HA

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant preparare otto Ubuntu 24.04 puliti nei ruoli del README, con
management/API e rete cluster separate. Adattare IP, NIC, VIP e DNS in modo
coerente; verificare NTP, MTU, firewall, accesso ai registry e failure domain.
Su bare metal distribuire i tre control plane e i due load balancer su guasti
indipendenti. La guida costruisce il cluster Kubernetes; storage, ingress,
osservabilità, backup e hardening richiesti per produzione restano fasi esplicite.

`Vagrantfile.start` usa le stesse box, VM, CPU, RAM, NIC, MAC, disco da 80 GB e
forwarding API del percorso assistito, ma non configura nulla nel guest. I due
file condividono `.vagrant`: non alternarli sulle stesse istanze.

## 1. Sistema e reti

Avviare e mantenere la variabile in ogni comando:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh control1
```

Inventariare `ip -br link`, `ip -br address`, `ip route`, `lsblk` e `df -hT`.
La NIC 1 NAT deve conservare DHCP e default route; NIC 2 e NIC 3 devono essere
presenti ma prive di IPv4. Identificarle tramite i MAC deterministici:

| Nodo | Management | Cluster | MAC management | MAC cluster |
| --- | --- | --- | --- | --- |
| `lb1` | `192.168.65.2` | `10.65.0.2` | `08:00:27:41:01:02` | `08:00:27:41:01:03` |
| `lb2` | `192.168.65.3` | `10.65.0.3` | `08:00:27:41:02:02` | `08:00:27:41:02:03` |
| `control1` | `192.168.65.11` | `10.65.0.11` | `08:00:27:41:03:02` | `08:00:27:41:03:03` |
| `control2` | `192.168.65.12` | `10.65.0.12` | `08:00:27:41:04:02` | `08:00:27:41:04:03` |
| `control3` | `192.168.65.13` | `10.65.0.13` | `08:00:27:41:05:02` | `08:00:27:41:05:03` |
| `worker1` | `192.168.65.21` | `10.65.0.21` | `08:00:27:41:06:02` | `08:00:27:41:06:03` |
| `worker2` | `192.168.65.22` | `10.65.0.22` | `08:00:27:41:07:02` | `08:00:27:41:07:03` |
| `worker3` | `192.168.65.23` | `10.65.0.23` | `08:00:27:41:08:02` | `08:00:27:41:08:03` |

Su ciascun nodo impostare il proprio hostname e creare un netplan analogo al
seguente, sostituendo MAC e suffisso IP:

```bash
sudo hostnamectl set-hostname control1
sudoedit /etc/netplan/60-infra-lab.yaml
```

```yaml
network:
  version: 2
  ethernets:
    enpmgmt:
      match: {macaddress: "08:00:27:41:03:02"}
      set-name: enpmgmt
      addresses: [192.168.65.11/24]
    enpcluster:
      match: {macaddress: "08:00:27:41:03:03"}
      set-name: enpcluster
      addresses: [10.65.0.11/24]
      link-local: []
```

```bash
sudo chmod 0600 /etc/netplan/60-infra-lab.yaml
sudo netplan generate
sudo netplan try
sudo netplan apply
```

Non configurare gateway o DNS sulle due NIC del lab. Inserire su tutti i nodi:

```text
# BEGIN K8S LAB
192.168.65.5 kube-api.lab.test kube-api
10.65.0.2 lb1
10.65.0.3 lb2
10.65.0.11 control1
10.65.0.12 control2
10.65.0.13 control3
10.65.0.21 worker1
10.65.0.22 worker2
10.65.0.23 worker3
# END K8S LAB
```

Verificare una sola default route sulla NAT, risoluzione nomi, NTP e ping
completi sulla rete `10.65.0.0/24`. Dal Bosgame gli IP management sono
raggiungibili; la rete cluster resta interna a VirtualBox.

Su tutti i nodi installare i prerequisiti comuni:

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gpg chrony
sudo systemctl enable --now chrony
```

Su control plane e worker disabilitare swap, caricare `overlay` e `br_netfilter`,
abilitare forwarding/bridge netfilter, quindi installare containerd con cgroup
driver `systemd`. Aggiungere il repository `pkgs.k8s.io` del ramo `v1.37`,
installare `kubelet kubeadm kubectl` e bloccarne le versioni con `apt-mark hold`.
Il provisioner `scripts/provision/k8s-control.sh` è una traccia leggibile dei
comandi, ma nel percorso manuale vanno eseguiti e verificati uno alla volta.
Non installare questi componenti sui due load balancer. Verificare almeno
`swapon --show`, `lsmod`, i tre valori `sysctl`, `containerd config dump`,
`systemctl status kubelet containerd` e `apt-mark showhold`.

Se è attivo un firewall, consentire le porte elencate nella documentazione
Kubernetes tra i ruoli corretti, VRRP IP protocol 112 tra i load balancer e
TCP 6443 verso HAProxy. Le porte host `16444` e `16445` ascoltano su
`0.0.0.0`: limitarle sul Bosgame alle sole reti amministrative.

## 2. Endpoint API ridondato

Installare HAProxy e Keepalived su `lb1` e `lb2`. HAProxy ascolta su `*:6443`
e controlla `10.65.0.11:6443`, `.12` e `.13`. Keepalived usa VRRP unicast
sulla NIC management, priorità 100/90 e VIP `192.168.65.5/24`.
Usare `scripts/provision/k8s-lb.sh` come riferimento per i file completi: i tre
backend HAProxy devono puntare alla rete cluster; ciascun peer Keepalived deve
puntare all'indirizzo management dell'altro LB e usare `enpmgmt`.

Prima di kubeadm verificare `haproxy -c -f /etc/haproxy/haproxy.cfg`, il listener
con `ss -ltnp | grep 6443` e la VIP con `ip address show dev enpmgmt`. Un test
TCP sulla VIP può aprirsi e poi chiudersi perché non esistono ancora backend
sani: non deve invece andare in timeout per un problema di routing o firewall.
Spegnere il LB che possiede la VIP, misurare il failover e riaccenderlo prima di
inizializzare il cluster.

## 3. Primo control plane

Su `control1` creare una configurazione kubeadm con:

- `controlPlaneEndpoint: kube-api.lab.test:6443`;
- `localAPIEndpoint.advertiseAddress: 10.65.0.11`;
- `networking.podSubnet: 10.244.0.0/16` e `serviceSubnet: 10.96.0.0/12`;
- `nodeRegistration.kubeletExtraArgs.node-ip: 10.65.0.11`;
- `apiServer.certSANs` con nome e VIP **più** gli indirizzi di `api_sans` in
  `lab.json`: il certificato copre solo ciò che è elencato;
- `KubeletConfiguration.cgroupDriver: systemd`.

Poi inizializzare e conservare gli output fuori dal repository. Le SAN si
possono dichiarare nel file oppure, equivalentemente, sulla riga di comando:

```bash
sudo kubeadm init --config kubeadm-init.yaml --upload-certs \
  --apiserver-cert-extra-sans 192.168.65.5,kube-api.lab.test,127.0.0.1,192.168.142.57,100.102.0.122,aipc.olm-velociraptor.ts.net
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
```

Fuori da questo host sostituire gli indirizzi con quelli reali. Se il cluster è
già inizializzato senza le SAN giuste, rigenerare il certificato dell'API con la
procedura kubeadm ufficiale, dopo avere salvato una copia di configurazione,
certificati ed etcd. Non rimuovere chiavi su un cluster importante senza backup.

Generare i kubeconfig per host e Mac dalla cartella del lab sul Bosgame:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start ./scripts/kubeconfig.sh
```

Il token e la certificate key sono credenziali temporanee: non inserirli in
file versionati. Rigenerarli con `kubeadm token create --print-join-command` e
`kubeadm init phase upload-certs --upload-certs` quando scadono.

## 4. CNI e join

Installare Cilium `1.20.1` seguendo la guida kubeadm ufficiale e impostare i
device/indirizzi coerenti con `enpcluster` e `10.65.0.0/24`. Verificare lo stato
prima dei join. Eseguire il comando `kubeadm join ... --control-plane
--certificate-key ...` su control2 e control3, aggiungendo l'indirizzo locale
del rispettivo nodo. Eseguire il join senza `--control-plane` sui tre worker.

```bash
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl get --raw='/readyz?verbose'
```

## 5. Criteri di collaudo

Verificare DNS, NetworkPolicy default-deny/allow, distribuzione pod,
PodDisruptionBudget, rolling update, drain e ritorno di un worker. Spegnere un
control plane alla volta e controllare API ed etcd; spegnere un LB alla volta e
controllare la VIP e, dal Mac, che l'accesso continui sull'altra porta pubblicata
(`16444`/`16445`). Provare snapshot e restore etcd in una copia sacrificabile
del lab. Aggiungere poi ingress, MetalLB/L2, CSI con storage realmente replicato,
monitoring, audit e backup esterno: sono parti necessarie di una piattaforma di
produzione, fuori dalla base attuale.

Esempio di fault test dal percorso manuale:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt lb1
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up lb1
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt worker3
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up worker3
```

Non spegnere contemporaneamente due control plane: lo stacked etcd perderebbe
il quorum. Attendere il ritorno `Ready` e la salute di etcd tra una prova e la
successiva.

## Arresto e reset

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```

`destroy` elimina in modo irreversibile cluster, etcd e volumi locali. Per
passare al percorso assistito, distruggere prima usando ancora `Vagrantfile.start`,
poi avviare senza la variabile.

Fonti: [HA con kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/),
[container runtime](https://kubernetes.io/docs/setup/production-environment/container-runtimes/),
[porte](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) e
[Cilium con kubeadm](https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/).
