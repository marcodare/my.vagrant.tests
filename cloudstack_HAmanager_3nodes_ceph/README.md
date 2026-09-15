# cloudstack_HAmanager_3nodes_ceph

Per studiare tutto a mano usare `Vagrant.start` e seguire [STEPS.md](STEPS.md).
Il `Vagrantfile` mantiene il percorso assistito già disponibile.

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito
VAGRANT_VAGRANTFILE=Vagrant.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh mgmt1
```

Nel percorso basic continuare con STEPS.md. Usare la variabile anche per
`status`, `halt` e `destroy`; non alternare i due file sulle stesse VM.

Versione richiesta: **CloudStack 4.23** (patch del ramo consentite).

Laboratorio di **HA da costruire e verificare**, con tre manager e tre KVM/storage
ceph. Due reti: fake public host-only 192.168.62.0/24 e privata internal
10.62.0.0/24. La NIC NAT tecnica di Vagrant resta separata. Solo questo lab acceso.
Tutti i file necessari alla definizione delle VM sono locali e modificabili.

## Topologia

| Nodi | Fake public / cloudbr1 | Private / cloudbr0 | RAM per nodo | vCPU | Dischi GB |
| --- | --- | --- | --- | --- | --- |
| mgmt1/2/3 | 192.168.62.11/.12/.13 | 10.62.0.11/.12/.13 | 8 GiB | 4 | OS 80 |
| kvm1/2/3 | 192.168.62.21/.22/.23 | 10.62.0.21/.22/.23 | 20 GiB | 6 | OS 80 + dati 200 |

Totale **84 GiB**, lasciando RAM all'host. I workload annidati consumano la RAM
già assegnata ai KVM: con un nodo perso occorre capacità libera sui superstiti.
Private porta management/storage e VLAN guest; fake public simula gli IP esterni.

## Cosa prepara Vagrant

```bash
vagrant validate
./scripts/up.sh
```

Crea sei VM, configura reti/DNS/NAT del lab, installa manager/MySQL/router,
HAProxy/Keepalived, agent KVM e pacchetti ceph. Nessun disco dati viene
formattato. I manager rimangono fermi finché non esistono schema e chiavi comuni:
**una risposta 503 della VIP iniziale è prevista**, non indica HA già operativa.

## Costruire il cluster

1. [Control plane](docs/control-plane.md): schema unico, MySQL InnoDB Cluster
   single-primary, router locali, tre manager con chiavi comuni e agent multihost.
2. [Storage](docs/storage.md): replica primaria e servizio NFS secondario ridondato.
3. Import System VM, zona Advanced e offering shared; verificare la prima VM.
4. Matrice di test: failover DB/UI/storage e migrazione a caldo.

VIP riservati: gateway/DNS **.4** e API **.5** su entrambe le reti;
secondario NFS **10.62.0.7**. Nel lab LINSTOR, controller VIP **10.62.0.6**.
Non assegnare questi IP a guest manuali. UI finale: **http://192.168.62.5/client/**.

## Limiti espliciti

Questo è uno scaffold eseguibile di nodi e pacchetti con runbook di assemblaggio,
non un deployment HA completo già collaudato. InnoDB Cluster/schema CloudStack,
NFS distribuito e nested KVM vanno validati sul Bosgame. La funzione CloudStack
**Host HA richiede OOBM/fencing**: VirtualBox non espone un BMC/IPMI pronto all'uso.
Non simulare conferme di fencing false; distinguere live migration, HA dei
servizi e restart dopo guasto del compute. Nessuna protezione dal guasto fisico
dell'unico Bosgame/SSD; connessioni NAT in corso possono cadere al cambio gateway.

## Stop e ripresa

Seguire il runbook per spegnere workload e cluster in ordine, poi `vagrant halt`.
Alla ripresa attendere quorum storage e DB prima di riavviare i manager.
`vagrant destroy` elimina tutti i dischi e database: usarlo solo per reset voluto.
Non serve distruggere questo lab per passare a un altro.
