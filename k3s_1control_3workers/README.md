# k3s: un control plane e tre worker

Laboratorio didattico K3s su Ubuntu 24.04: quattro VM, 32 GiB RAM e due reti
del lab. La rete host-only `192.168.64.0/24` serve per amministrazione; la rete
interna `10.64.0.0/24` porta API, traffico tra nodi e overlay Flannel.

| Nodo | Management | Cluster | Ruolo |
| --- | --- | --- | --- |
| control1 | 192.168.64.10 | 10.64.0.10 | server/control plane |
| worker1 | 192.168.64.21 | 10.64.0.21 | agent |
| worker2 | 192.168.64.22 | 10.64.0.22 | agent |
| worker3 | 192.168.64.23 | 10.64.0.23 | agent |

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito fino ai prerequisiti
VAGRANT_VAGRANTFILE=Vagrant.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh control1
```

Seguire [STEPS.md](STEPS.md). Il `Vagrantfile` normale configura OS, hostname,
reti e prerequisiti, ma lascia comunque l'installazione K3s come esercizio.
Usare la variabile anche per `status`, `halt` e `destroy`; non alternare i due
file sulle stesse VM.
K3s è fissato a `v1.36.4+k3s1`, versione del canale stable verificata il
15 settembre 2026.

Il singolo server è intenzionalmente un punto di guasto: serve per capire il
join degli agent e il comportamento dei workload, non l'HA del control plane.
