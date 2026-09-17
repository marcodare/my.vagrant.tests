# Configurazione manuale K3s

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant usare quattro Ubuntu 24.04 puliti con una rete di management e
una rete cluster comune. Gli IP sono un profilo di riferimento: adattarli insieme
a hostname, NIC, DNS e regole firewall, mantenendo una route verso Internet e
NTP stabile. Su bare metal verificare anche MTU, ridondanza switch e dischi.
Il passo Vagrant seguente si salta; la configurazione parte dall'inventario rete.

`Vagrantfile.start` usa le stesse box, VM, CPU, RAM, NIC, MAC, disco da 80 GB e
forwarding API del percorso assistito, ma non configura nulla nel guest. I due
file condividono `.vagrant`: non alternarli sulle stesse istanze.

## 1. Avvio e rete

Avviare e mantenere la variabile in ogni comando:

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant status
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh control1
```

Inventariare `ip -br link`, `ip -br address`, `ip route`, `lsblk` e `df -hT`.
La NIC 1 NAT deve conservare DHCP e default route; NIC 2 e NIC 3 devono essere
presenti ma prive di IPv4. Identificarle tramite i MAC deterministici:

| Nodo | MAC management | MAC cluster |
| --- | --- | --- |
| `control1` | `08:00:27:42:01:02` | `08:00:27:42:01:03` |
| `worker1` | `08:00:27:42:02:02` | `08:00:27:42:02:03` |
| `worker2` | `08:00:27:42:03:02` | `08:00:27:42:03:03` |
| `worker3` | `08:00:27:42:04:02` | `08:00:27:42:04:03` |

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
      match: {macaddress: "08:00:27:42:01:02"}
      set-name: enpmgmt
      addresses: [192.168.64.10/24]
    enpcluster:
      match: {macaddress: "08:00:27:42:01:03"}
      set-name: enpcluster
      addresses: [10.64.0.10/24]
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
# BEGIN K3S LAB
10.64.0.10 control1
10.64.0.21 worker1
10.64.0.22 worker2
10.64.0.23 worker3
# END K3S LAB
```

Verificare una sola default route sulla NAT, risoluzione dei quattro nomi e
ping completi sulla rete `10.64.0.0/24`. Dal Bosgame gli IP management sono
raggiungibili; la rete cluster resta interna a VirtualBox.

## 2. Prerequisiti

Su tutti i nodi installare i pacchetti minimi e rendere persistenti moduli e
sysctl:

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl chrony
sudo systemctl enable --now chrony
cat <<'EOF' | sudo tee /etc/modules-load.d/kubernetes.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<'EOF' | sudo tee /etc/sysctl.d/90-kubernetes.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
```

Verificare `chronyc tracking`, `lsmod`, i tre valori `sysctl` e la risoluzione
di ogni hostname sull'indirizzo `10.64.0.x`. Se è attivo un firewall, consentire
almeno API TCP 6443, kubelet TCP 10250 e Flannel VXLAN UDP 8472 fra i nodi.

## 3. Server

Su `control1` scegliere un token casuale e non salvarlo nel repository:

Il certificato dell'API copre solo gli indirizzi dichiarati: ogni `--tls-san`
corrisponde a un modo di raggiungere il cluster. Senza quello dell'host, kubectl
dal Mac fallirebbe la verifica TLS. L'elenco sta in `api_sans` di `lab.json`.

```bash
read -rsp 'Token K3s: ' K3S_TOKEN; echo
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION='v1.36.4+k3s1' \
  K3S_TOKEN="$K3S_TOKEN" sh -s - server \
  --node-ip 10.64.0.10 --advertise-address 10.64.0.10 \
  --flannel-iface enpcluster --write-kubeconfig-mode 600 \
  --secrets-encryption \
  --tls-san 192.168.64.10 \
  --tls-san 127.0.0.1 \
  --tls-san 192.168.142.57 \
  --tls-san 100.102.0.122 \
  --tls-san aipc.olm-velociraptor.ts.net
sudo k3s kubectl get nodes
```

Se il nome dell'interfaccia scelto durante la configurazione manuale è diverso,
sostituire `enpcluster`. Fuori da questo host, sostituire gli indirizzi dei
`--tls-san` con quelli con cui si raggiungerà davvero l'API.

Generare i kubeconfig per host e Mac (dalla cartella del lab, sul Bosgame):

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start ./scripts/kubeconfig.sh
```

## 4. Worker

Ripetere su ogni worker, mantenendo il token solo nella shell corrente:

```bash
read -rsp 'Token K3s: ' K3S_TOKEN; echo
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION='v1.36.4+k3s1' \
  K3S_TOKEN="$K3S_TOKEN" sh -s - agent \
  --server https://10.64.0.10:6443 --node-ip 10.64.0.21 \
  --flannel-iface enpcluster
```

Cambiare l'ultimo ottetto per worker2 e worker3. Dal control verificare nodi,
pod di sistema, DNS, Traefik e local-path storage con `kubectl get ... -A`.

## 5. Verifiche e fault test

Creare un Deployment con almeno tre repliche, un Service, una NetworkPolicy e
un volume. Spegnere un worker e osservare rescheduling e tempi di recupero.
Studiare backup/restore e rotazione della cifratura dei Secret. Prima di fermare
il lab usare `kubectl drain` sui worker.

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A -o wide
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt worker3
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up worker3
```

Attendere che il nodo torni `Ready`; con il solo `control1` spento API e
scheduling non sono disponibili, perché questo non è un control plane HA.

## Arresto e reset

```bash
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant halt
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant destroy
```

`destroy` elimina in modo irreversibile cluster e volumi locali. Per passare al
percorso assistito, distruggere prima usando ancora `Vagrantfile.start`, poi avviare
senza la variabile.

Fonti: [requisiti K3s](https://docs.k3s.io/installation/requirements),
[opzioni server](https://docs.k3s.io/cli/server) e
[upgrade manuali](https://docs.k3s.io/upgrades/manual).
