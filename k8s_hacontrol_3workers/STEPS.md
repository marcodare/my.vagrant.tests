# Configurazione manuale Kubernetes HA

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant preparare otto Ubuntu 24.04 puliti nei ruoli del README, con
management/API e rete cluster separate. Adattare IP, NIC, VIP e DNS in modo
coerente; verificare NTP, MTU, firewall, accesso ai registry e failure domain.
Su bare metal distribuire i tre control plane e i due load balancer su guasti
indipendenti. La guida costruisce il cluster Kubernetes; storage, ingress,
osservabilità, backup e hardening richiesti per produzione restano fasi esplicite.

## 1. Sistema e reti

Avviare con `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. Configurare hostname,
`/etc/hosts`, NIC 2 management `192.168.65.<host>/24` e NIC 3 cluster
`10.65.0.<host>/24`, senza gateway aggiuntivi. La NAT resta la default route.
Verificare risoluzione nomi, sincronizzazione NTP e connettività completa.

Su control plane e worker disabilitare swap, caricare `overlay` e `br_netfilter`,
abilitare forwarding/bridge netfilter, quindi installare containerd con cgroup
driver `systemd`. Aggiungere il repository `pkgs.k8s.io` del ramo `v1.37`,
installare `kubelet kubeadm kubectl` e bloccarne le versioni con `apt-mark hold`.
Il provisioner `scripts/provision/k8s-control.sh` è una traccia leggibile dei
comandi, ma nel percorso manuale vanno eseguiti e verificati uno alla volta.

## 2. Endpoint API ridondato

Installare HAProxy e Keepalived su `lb1` e `lb2`. HAProxy ascolta sulla VIP
`192.168.65.5:6443` e controlla `10.65.0.11:6443`, `.12` e `.13`. Keepalived usa
VRRP unicast sulla NIC management, priorità 100/90 e VIP `192.168.65.5/24`.
Verificare su quale LB si trova la VIP; spegnere quel LB e misurare il failover.
Prima di kubeadm, `nc -zv 192.168.65.5 6443` deve rispondere “refused”, non timeout.

## 3. Primo control plane

Su `control1` creare una configurazione kubeadm con:

- `controlPlaneEndpoint: kube-api.lab.test:6443`;
- `localAPIEndpoint.advertiseAddress: 10.65.0.11`;
- `networking.podSubnet: 10.244.0.0/16` e `serviceSubnet: 10.96.0.0/12`;
- `nodeRegistration.kubeletExtraArgs.node-ip: 10.65.0.11`;
- `apiServer.certSANs` contenente nome e VIP;
- `KubeletConfiguration.cgroupDriver: systemd`.

Poi inizializzare e conservare gli output fuori dal repository:

```bash
sudo kubeadm init --config kubeadm-init.yaml --upload-certs
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
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

Verificare DNS, NetworkPolicy default-deny/allow, distribuzione pod, PodDisruptionBudget,
rolling update, drain e ritorno di un worker. Spegnere un control plane alla volta
e controllare API ed etcd; spegnere un LB alla volta e controllare la VIP. Provare
snapshot e restore etcd in una copia sacrificabile del lab. Aggiungere poi ingress,
MetalLB/L2, CSI con storage realmente replicato, monitoring, audit e backup esterno:
sono parti necessarie di una piattaforma di produzione, fuori dalla base attuale.

Fonti: [HA con kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/),
[container runtime](https://kubernetes.io/docs/setup/production-environment/container-runtimes/),
[porte](https://kubernetes.io/docs/reference/networking/ports-and-protocols/) e
[Cilium con kubeadm](https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/).
