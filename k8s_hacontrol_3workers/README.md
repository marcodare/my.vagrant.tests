# Kubernetes HA: tre control plane e tre worker

Topologia kubeadm “production style” con stacked etcd, tre control plane, tre
worker e due load balancer HAProxy/Keepalived. Usa 8 VM e 68 GiB RAM.

La management/API è `192.168.65.0/24`, con VIP `192.168.65.5`. La rete interna
`10.65.0.0/24` trasporta API backend, etcd e traffico tra nodi. Control plane:
`.11-.13`; worker: `.21-.23`; load balancer: `.2-.3` su entrambi i segmenti.

| Nodi | Quantità | vCPU ciascuno | RAM ciascuno | Disco OS |
| --- | --- | --- | --- | --- |
| `lb1`, `lb2` | 2 | 2 | 4 GiB | 80 GB |
| `control1-3` | 3 | 4 | 8 GiB | 80 GB |
| `worker1-3` | 3 | 6 | 12 GiB | 80 GB |

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito fino ai prerequisiti
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrantfile.start vagrant ssh control1
```

Seguire [STEPS.md](STEPS.md). Il `Vagrantfile` normale configura reti, i due
load balancer, containerd e i pacchetti Kubernetes, ma lascia `kubeadm` e Cilium
come esercizio. Sono selezionati Kubernetes 1.37 e Cilium 1.20.1.
`Vagrantfile.start` dichiara le stesse box, VM, risorse, NIC, MAC, dischi e porte
API del percorso assistito, ma non contiene provisioner. Usare la variabile
anche per `status`, `ssh`, `halt`, `up` e `destroy`. I due file condividono
`.vagrant`: non alternarli sulle stesse istanze.

## kubectl dal Bosgame e dal Mac

Il VIP `192.168.65.5` vive sulla rete host-only e non esce dal Bosgame. Entrambi
i load balancer pubblicano quindi la 6443 su una porta dell'host, in ascolto su
tutte le interfacce: se `lb1` cade si usa la porta di `lb2`. I forwarding sono
presenti anche nel percorso basic e rispondono dopo l'installazione manuale di
HAProxy. Limitare `16444` e `16445` con il firewall del Bosgame alle reti
amministrative; non esporle direttamente a Internet.

| Da dove | Endpoint |
| --- | --- |
| Bosgame | `https://192.168.65.5:6443` (VIP) |
| Mac, via lb1 | `https://<indirizzo-bosgame>:16444` |
| Mac, via lb2 | `https://<indirizzo-bosgame>:16445` |

A cluster inizializzato:

```bash
./scripts/kubeconfig.sh                 # usa il primo valore di api_sans
./scripts/kubeconfig.sh 100.102.0.122   # oppure un indirizzo esplicito
```

Lo script scrive tre kubeconfig `.local.`, esclusi dal Git perché contengono
credenziali admin. HAProxy ascolta su tutte le interfacce, non solo sul VIP:
serve perché il port forward di VirtualBox arriva dalla NIC NAT.

`kubeadm init` va eseguito con `--apiserver-cert-extra-sans` che includa gli
indirizzi di `api_sans` in `lab.json`, altrimenti il certificato copre solo VIP e
nomi interni e kubectl dal Mac fallisce: vedere [STEPS.md](STEPS.md).

La topologia esercita quorum e failover dei servizi virtuali. Tutte le VM sono
sullo stesso Bosgame e sullo stesso SSD: non offre HA fisica e non va presentata
come ambiente di produzione reale. Mancano inoltre storage persistente HA,
backup esterno, monitoring, logging, gestione certificati e disaster recovery.

## Arresto e reset

Prima di spegnere il lab, drenare i worker quando possibile e verificare che
etcd sia sano. Nel percorso assistito:

```bash
vagrant halt
vagrant up
vagrant destroy    # distruttivo: elimina cluster, etcd e volumi locali
```

Nel percorso manuale anteporre sempre
`VAGRANT_VAGRANTFILE=Vagrantfile.start`. Per cambiare percorso distruggere prima
le istanze con la definizione usata per crearle.

## Limiti aggiuntivi

- Keepalived protegge il VIP soltanto sul singolo host VirtualBox.
- Lo stacked etcd tollera un control plane perso, non due.
- Il disco virtuale è portato a 80 GB, ma partizione e filesystem potrebbero
  richiedere un'espansione separata da verificare con `lsblk` e `df -h`.
- Il laboratorio è stato validato staticamente; kubeadm, Cilium, VIP, accesso
  remoto e fault test devono essere collaudati sul Bosgame.
