# Builder delle box locali

Questa cartella contiene definizioni riproducibili per costruire box Vagrant
destinate ai laboratori. Gli artefatti generati non sono versionati: ISO, dischi,
OVF/OVA e file `.box` sono ricreabili e possono contenere stato della macchina.

## Builder disponibili

| Cartella | Risultato | Stato |
| --- | --- | --- |
| [`proxmox/`](proxmox/README.md) | `local/proxmox-ve-9.2` per VirtualBox/amd64 | Definizione pronta, collaudo reale da eseguire |

Ogni builder deve:

- scaricare soltanto immagini ufficiali e verificarne checksum e firma;
- evitare credenziali persistenti nei file versionati;
- produrre una macchina generica, senza cluster o dati di un laboratorio;
- collocare gli output in directory ignorate da Git;
- documentare separatamente validazione statica e collaudo reale.

La creazione di una box avvia una VM temporanea e installa un sistema operativo.
Non viene eseguita da `scripts/validate.sh` e va avviata esplicitamente seguendo
il README del builder interessato.
