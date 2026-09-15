# Configurazione manuale K3s

## Uso su Vagrant, VM generiche o bare metal

Fuori da Vagrant usare quattro Ubuntu 24.04 puliti con una rete di management e
una rete cluster comune. Gli IP sono un profilo di riferimento: adattarli insieme
a hostname, NIC, DNS e regole firewall, mantenendo una route verso Internet e
NTP stabile. Su bare metal verificare anche MTU, ridondanza switch e dischi.
Il passo Vagrant seguente si salta; la configurazione parte dall'inventario rete.

## 1. Avvio e rete

Avviare con `VAGRANT_VAGRANTFILE=Vagrant.start vagrant up`. Su ogni nodo usare
`ip -br link` e i MAC mostrati da `VBoxManage showvminfo` per identificare NIC 2
e NIC 3. Impostare hostname, `/etc/hosts`, IP management `192.168.64.<host>/24`
e IP cluster `10.64.0.<host>/24`; lasciare il gateway predefinito sulla NIC NAT.
Verificare da ogni nodo `ping 10.64.0.10` e gli altri indirizzi cluster.

## 2. Prerequisiti

Su tutti i nodi abilitare `overlay`, `br_netfilter`, forwarding IPv4 e bridge
netfilter. Installare `curl`, sincronizzare l'orologio e verificare che ogni
hostname risolva sull'indirizzo `10.64.0.x`.

## 3. Server

Su `control1` scegliere un token casuale e non salvarlo nel repository:

```bash
read -rsp 'Token K3s: ' K3S_TOKEN; echo
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION='v1.36.4+k3s1' \
  K3S_TOKEN="$K3S_TOKEN" sh -s - server \
  --node-ip 10.64.0.10 --advertise-address 10.64.0.10 \
  --flannel-iface enpcluster --write-kubeconfig-mode 600 \
  --secrets-encryption
sudo k3s kubectl get nodes
```

Se il nome dell'interfaccia scelto durante la configurazione manuale è diverso,
sostituire `enpcluster`.

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

## 5. Esercizi

Creare un Deployment con almeno tre repliche, un Service, una NetworkPolicy e
un volume. Spegnere un worker e osservare rescheduling e tempi di recupero.
Studiare backup/restore e rotazione della cifratura dei Secret. Prima di fermare
il lab usare `kubectl drain` sui worker; poi `vagrant halt`.

Fonti: [requisiti K3s](https://docs.k3s.io/installation/requirements),
[opzioni server](https://docs.k3s.io/cli/server) e
[upgrade manuali](https://docs.k3s.io/upgrades/manual).
