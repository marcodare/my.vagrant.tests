# Kubernetes HA: tre control plane e tre worker

Topologia kubeadm “production style” con stacked etcd, tre control plane, tre
worker e due load balancer HAProxy/Keepalived. Usa 8 VM e 68 GiB RAM.

La management/API è `192.168.65.0/24`, con VIP `192.168.65.5`. La rete interna
`10.65.0.0/24` trasporta API backend, etcd e traffico tra nodi. Control plane:
`.11-.13`; worker: `.21-.23`; load balancer: `.2-.3` su entrambi i segmenti.

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito fino ai prerequisiti
VAGRANT_VAGRANTFILE=Vagrant.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh control1
```

Seguire [STEPS.md](STEPS.md). Il `Vagrantfile` normale configura reti, i due
load balancer, containerd e i pacchetti Kubernetes, ma lascia `kubeadm` e Cilium
come esercizio. Sono selezionati Kubernetes 1.37 e Cilium 1.20.1.
Usare la variabile anche per `status`, `halt` e `destroy`; non alternare i due
file sulle stesse VM.

La topologia esercita quorum e failover dei servizi virtuali. Tutte le VM sono
sullo stesso Bosgame e sullo stesso SSD: non offre HA fisica e non va presentata
come ambiente di produzione reale. Mancano inoltre storage persistente HA,
backup esterno, monitoring, logging, gestione certificati e disaster recovery.
