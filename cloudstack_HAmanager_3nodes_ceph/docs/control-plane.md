# Control plane: procedura di studio

Nei comandi sostituire S con **61** (LINSTOR) oppure **62** (Ceph). Non eseguire
comandi con S letterale. L'ordine è importante: schema → cluster DB → router →
manager → storage → zona. Provisioning non forma automaticamente questi cluster.

## 1. Schema unico e MySQL InnoDB Cluster

La base installa MySQL 8.0 su mgmt1/2/3, con GTID e server-id distinti. Installare
**MySQL Shell 8.0** compatibile sui control node seguendo il
[repository Oracle](https://dev.mysql.com/doc/mysql-apt-repo-quick-guide/en/).
Non aggiornare accidentalmente server/router a un altro major usando il repository.
Controllare `mysql --version`, `mysqlsh --version` e `mysqlrouter --version`.

Prima della replica, inizializzare lo schema **solo su mgmt1**, con manager
ancora fermo. Usare la procedura
[CloudStack setup databases](https://docs.cloudstack.apache.org/en/4.23.0.0/installguide/management-server/index.html):
`cloudstack-setup-databases cloud:<password>@localhost --deploy-as=<admin>:<password>
-e file -m <management-key> -k <database-key> -i 10.S.0.11`.
Scegliere segreti nuovi; non copiare questi segnaposto letteralmente. Preparare
l'account MySQL di deploy locale con permessi necessari, eliminarlo dopo il setup.
Non usare un'altra esecuzione di setup per creare tre schemi indipendenti.

In una sessione MySQL Shell sul nodo (root tramite socket locale), usando la
modalità **Python** `mysqlsh --py`, preparare ogni istanza con
`dba.configure_instance()`. Creare con AdminAPI un account cluster amministrativo
che possa raggiungere i tre IP privati (password interattiva, mai nel repo).
La configurazione deve passare `dba.check_instance_configuration(...)`, incluso
il controllo delle tabelle CloudStack: Group Replication richiede chiavi adatte.
**Se il controllo dello schema fallisce, fermarsi e registrare l'incompatibilità;
non forzare il cluster, non modificare a caso lo schema CloudStack.**
È un rischio concreto: l'[issue upstream #6670](https://github.com/apache/cloudstack/issues/6670)
riporta incompatibilità di tabelle MEMORY, fra cui op_lock, con Group Replication.
Controllare lo schema effettivo della 4.23: non assumere che il cambio versione
renda automaticamente supportato InnoDB Cluster.

Da MySQL Shell connessa come amministratore cluster a 10.S.0.11:

```python
cluster = dba.create_cluster('cloudstack', {'communicationStack': 'MYSQL'})
cluster.add_instance('clusteradmin@10.S.0.12:3306', {'recoveryMethod': 'clone'})
cluster.add_instance('clusteradmin@10.S.0.13:3306', {'recoveryMethod': 'clone'})
cluster.status({'extended': 1})
```

Clone sostituisce i dati locali dei due joiner: usarlo solo su mgmt2/3 vuoti.
Risultato richiesto: tre membri ONLINE, **single primary**, due secondary.
Questa integrazione DB è un percorso sperimentale da verificare con lo schema
CloudStack installato, non una certificazione upstream della combinazione.

## 2. Router locale su ogni manager

Da root su ogni manager, con password richiesta dal tool:

```bash
mysqlrouter --bootstrap clusteradmin@10.S.0.11:3306 --user=mysqlrouter --conf-bind-address=127.0.0.1
systemctl enable --now mysqlrouter
```

Controllare che il listener read/write sia **127.0.0.1:6446** e instradi al
primary corrente. Tutti i manager useranno il proprio router, mai il MySQL locale
direttamente sulla 3306 (potrebbe essere una replica read-only).

## 3. Segreti comuni e servizi CloudStack

Sui manager aggiuntivi eseguire `cloudstack-setup-databases` **senza --deploy-as**,
come da guida 4.23, usando le medesime credenziali cloud, management encryption
key e database encryption key del primo nodo, e il proprio IP privato con -i.
Usare il primary corrente per questo setup iniziale; poi impostare il router
locale come sotto. Conservare i segreti in un gestore sicuro, mai nel repository;
non generarne di diversi sui tre nodi. Il setup crea la configurazione client,
non tre database indipendenti.

In `db.properties` su ciascun manager impostare:

```properties
db.cloud.host=127.0.0.1
db.cloud.port=6446
db.usage.host=127.0.0.1
db.usage.port=6446
```

Mantenere le password cifrate generate, verificare inoltre che l'indirizzo del
nodo manager sia il proprio IP privato (non copiare 10.S.0.11 su tutti).
Eseguire `cloudstack-setup-management` su ciascuno e, solo dopo il successo,
`touch /var/lib/infra-lab/management-ready`. Il marker evita che un successivo
provisioning fermi intenzionalmente un manager già configurato.

UI bilanciata: **http://192.168.S.5/client/**. Se 503, controllare prima DB e
backend manager. Il VIP/gateway .4 e la UI .5 sono gestiti da Keepalived su
mgmt1/2/3; HAProxy sulla porta 80 evita conflitti con i manager sulla 8080.

Prima di registrare KVM e System VM, impostare nella UI:

- `host`: `10.S.0.11,10.S.0.12,10.S.0.13`.
- `indirect.agent.lb.algorithm`: `roundrobin`.
- `indirect.agent.lb.check.interval`: un intervallo non nullo adatto al test.

Gli agent contattano direttamente i tre manager; le connessioni non passano
attraverso un unico proxy TCP. Verificare i tre manager online e la propagazione
della lista agli agent. Vedere [HA CloudStack](https://docs.cloudstack.apache.org/en/4.23.0.0/adminguide/reliability.html).

## 4. SSH degli host e zona

Su ciascun KVM impostare `sudo passwd vagrant`, consentire PasswordAuthentication
in `/etc/ssh/sshd_config.d/00-infra-bootstrap.conf` e validare/ricaricare sshd.
Verificare dal manager l'accesso a 10.S.0.21/.22/.23. L'utente deve avere sudo.
Lo storage distribuito usa il disco raw da 200 GB: **non formattarlo come locale**.
Completare [storage.md](storage.md) e solo dopo importare System VM e creare zona.

| Campo zona Advanced | Valore |
| --- | --- |
| Physical public | cloudbr1; traffic Public, untagged |
| Physical private | cloudbr0; traffic Management/Storage/Guest |
| DNS esterno / interno | 192.168.S.4 / 10.S.0.4 |
| Gateway pod | 10.S.0.4, maschera 255.255.255.0 |
| System IP pool | 10.S.0.50–10.S.0.79 |
| Public gateway | 192.168.S.4, maschera 255.255.255.0 |
| Public pool | 192.168.S.100–192.168.S.199 |
| VLAN guest | 100–199; tenant CIDR es. 172.20.100.0/24 |
| KVM | 10.S.0.21, .22, .23 |
| Storage offering | shared/distributed, NON local |

Impostare `use.local.storage=false` e `system.vm.use.local.storage=false`.
Usare una network offering con router ridondanti per testare il percorso di
rete dei tenant; i router singoli restano un punto di guasto separato.

## 5. Matrice di accettazione HA

Provare un guasto alla volta con workload sacrificabile, dopo avere ottenuto
quorum sano. Prima fare failover del servizio, poi simulare power-off di una VM.

| Prova | Evidenza richiesta |
| --- | --- |
| Fermare un manager | UI/API tramite VIP, task nuovi e agent riconnessi |
| Fermare il primary MySQL | Elezione nuovo primary; router R/W; scritture riuscite |
| Spegnere il proprietario VIP | VIP su superstite, nuova sessione UI/DNS funzionante |
| Fermare controller LINSTOR / MON Ceph | API storage e I/O disponibili |
| Perdere nodo primary storage | I/O continua con due copie/nodi superstiti |
| Perdere nodo NFS secondario | template/backup ancora accessibili via VIP |
| Live migration VM | task completato, disco condiviso, ping e scritture coerenti |
| VM HA dopo guasto KVM | fencing verificato prima di qualunque riavvio altrove |

**Host HA non è automaticamente disponibile:** VirtualBox non espone un BMC
IPMI ai guest. CloudStack richiede OOBM/fencing per la sua funzione Host HA.
Non abilitare fake fencing che risponde successo senza spegnere il vecchio nodo.
La live migration e la ridondanza dei servizi si possono testare separatamente;
il failover su partizione di rete resta un test bloccato finché non c'è fencing
reale del nodo virtuale. Il solo guasto certo mediante power-off non dimostra
che un guasto ambiguo venga gestito correttamente.

Il gateway simulato cambia nodo con VRRP ma non replica conntrack: le sessioni
NAT già aperte possono interrompersi. La ridondanza è fra VM sul medesimo
Bosgame, non protegge dalla perdita dell'host/SSD.

## Arresto e ripresa

Spegnere workload e System VM. Con storage sano fermare i servizi ordinatamente,
poi `vagrant halt`. Riavviare KVM/storage e tutti i control node; attendere quorum.
Dopo spegnimento totale MySQL usare la procedura ufficiale
`dba.reboot_cluster_from_complete_outage()` verificando l'istanza più aggiornata,
mai forzando bootstrap su una replica arbitraria. Riprendere i manager dopo DB,
router e storage. `vagrant destroy` è reset distruttivo di tutti i dati del lab.
