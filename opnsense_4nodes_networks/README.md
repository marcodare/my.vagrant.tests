# OPNsense fra quattro Debian su tre reti

Laboratorio per studiare un firewall/router fra segmenti: quattro Debian 13
distribuiti su tre reti interne e un OPNsense 26.1 che le collega. Ogni flusso
fra segmenti diversi attraversa il firewall, dove si osservano stati, regole,
NAT e log. Cinque VM, 20 GiB RAM.

| Nodo | Sistema | Management | Segmento interno |
| --- | --- | --- | --- |
| blue1 | Debian 13 | 192.168.67.11 | blue 10.67.1.11 |
| blue2 | Debian 13 | 192.168.67.12 | blue 10.67.1.12 |
| green1 | Debian 13 | 192.168.67.13 | green 10.67.2.13 |
| dmz1 | Debian 13 | 192.168.67.14 | dmz 10.67.3.14 |
| opnsense | OPNsense 26.1 su FreeBSD 14.3 | 192.168.67.10 (LAN/MGMT) | 10.67.1.1, 10.67.2.1, 10.67.3.1 |

Interfacce OPNsense: NIC 1 NAT = **WAN** (DHCP, uscita Internet e `vagrant
ssh`), NIC 2 host-only = **LAN/MGMT** con la GUI su `https://192.168.67.10`,
NIC 3–5 = **OPT1 BLUE**, **OPT2 GREEN**, **OPT3 DMZ**. I Debian hanno NIC NAT,
NIC di management e una NIC sul proprio segmento, con rotte verso gli altri
segmenti via OPNsense; la default route resta sulla NAT finché un esercizio
non la sposta sul firewall.

Regole di partenza: BLUE e GREEN possono iniziare qualunque flusso; DMZ non ha
regole, quindi non può iniziare nulla ma risponde alle connessioni in ingresso.
Il resto è esercizio.

## OPNsense: da FreeBSD con il metodo ufficiale

Non esiste una box Vagrant ufficiale OPNsense. Il lab parte dalla box
`bento/freebsd-14.3` e la converte con
[opnsense-bootstrap](https://github.com/opnsense/update), lo strumento del
progetto che trasforma un FreeBSD pulito in OPNsense. Il ramo è **26.1**
(basato su FreeBSD 14); 26.7 richiede FreeBSD 15, per cui non esiste ancora
una box Bento. Il bootstrap scarica pacchetti e set dal repository OPNsense e
richiede alcuni minuti; al termine la VM si riavvia da sola.

Il provisioner scrive una `config.xml` minima: interfacce, utente `vagrant`
con chiave SSH e `sudo`, SSH sulla WAN per Vagrant, le regole iniziali. La
password di `root` è quella di default di OPNsense e il wizard della GUI ne
chiede il cambio al primo accesso: farlo subito.

Alternativa: una box locale `local/opnsense-26.1` costruita a mano dall'ISO
ufficiale, con avvio immediato. La procedura completa è in
[CREATE_BOX_OPNSENSE.md](CREATE_BOX_OPNSENSE.md); il lab non la usa ancora per
default (vedere la sezione finale di quel documento).

## Due percorsi di avvio

```bash
./scripts/up.sh                                      # assistito
VAGRANT_VAGRANTFILE=Vagrant.start vagrant up        # basic/manuale
VAGRANT_VAGRANTFILE=Vagrant.start vagrant ssh opnsense
```

Nel percorso basic il nodo `opnsense` è un FreeBSD pulito: conversione,
assegnazione interfacce e regole sono in [STEPS.md](STEPS.md), che copre anche
Debian e le verifiche. Usare la variabile anche per `status`, `halt` e
`destroy`; non alternare i due file sulle stesse VM.

## Operazioni

```bash
vagrant status
vagrant ssh blue1               # oppure blue2, green1, dmz1, opnsense
vagrant halt                    # conserva lo stato su disco
vagrant up                      # riprende le VM già configurate
vagrant destroy                 # reset distruttivo, chiede conferma
```

La console di `opnsense` è visibile in VirtualBox (`gui = true`): serve se
SSH non è raggiungibile, per esempio dopo una regola sbagliata sulla WAN.
Per uno spegnimento ACPI pulito installare il plugin `os-virtualbox`.

## Esercizi suggeriti

- `iperf3 -s` su green1 e client da blue1: seguire il flusso in *Firewall: Log
  Files: Live View* e con `tcpdump -ni em3` sul firewall.
- Aggiungere una regola che blocchi ICMP da BLUE a DMZ e verificarla.
- Aprire un servizio in DMZ (`python3 -m http.server`) solo verso GREEN.
- Consentire alla DMZ l'uscita verso Internet e nulla verso BLUE/GREEN.
- Spostare la default route dei Debian su OPNsense e usare Unbound come DNS.
- Port forward dalla WAN a un servizio in DMZ e NAT reflection.

## Limiti

- Provisioning OPNsense non collaudato: bootstrap, `config.xml` generata e
  accesso `vagrant ssh` dopo il riavvio vanno verificati sul Bosgame. In caso
  di problemi la console VirtualBox e STEPS.md permettono di completare a mano.
- La NAT VirtualBox non permette a un altro host di raggiungere la WAN:
  i port forward si provano dal Bosgame o dai Debian.
- Il disco della box FreeBSD non viene esteso; quelli Debian sì (80 GB), ma
  la crescita di partizione e filesystem nel guest non è automatica.
- 26.1 riceve aggiornamenti finché il progetto la supporta; passare a 26.7
  quando sarà disponibile una box FreeBSD 15 (aggiornare `versions` e
  `ROLE_BOXES` nel validatore).
