# Esercizio Ceph su tre nodi

Applicabile ai lab `ceph` e `ceph_backup`. Prima completare cluster e controllo
KVM del [runbook PVE](proxmox.md). Un disco dati raw da 100 GB per nodo; nessun
OSD viene creato automaticamente. Tutte le operazioni seguenti sono nei guest.

1. Da UI, su ciascun nodo, aprire **Ceph → Install Ceph** e scegliere la stessa
   versione supportata da PVE 9.2 (Squid) e il repository no-subscription. Usare
   il wizard evita di duplicare a mano repository e versioni del pacchetto.
2. Sul primo nodo inizializzare Ceph: public network **10.58.1.0/24**, oppure
   **10.59.1.0/24** nel lab backup. Anche la rete cluster/replica usa lo stesso
   segmento (lasciare cluster network vuota o impostarla uguale).
3. Creare un **MON per nodo** e almeno due **MGR** su nodi diversi. Verificare
   quorum MON nella schermata Ceph. Management/Corosync restano su vmbr0.
4. Per ogni nodo, prima di creare l'OSD:

   ```bash
   lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
   ```

   Identificare il disco aggiuntivo **100 GB**, senza filesystem o partizioni.
   In **Ceph → OSD → Create OSD** scegliere quel disco. Non scegliere il disco
   OS da 80 GB; la creazione OSD sovrascrive il disco selezionato.
5. Creare pool **ceph-vm**, replica **size=3**, **min_size=2**, failure domain
   **host**, autoscaler abilitato; selezionare **Add as Storage**. Deve risultare
   storage RBD condiviso su tutti i nodi.
6. Attendere PG active+clean e verificare:

   ```bash
   ceph -s
   ceph osd tree
   ceph df
   pvesm status
   ```

Con 3 × 100 GB e tre repliche, capacità teorica utile circa 100 GB prima di
overhead e soglie di riempimento. Usare poche VM piccole e mantenere ampio spazio
libero; tre VDI sullo stesso SSD non sono tre domini di guasto fisici.

## Esperimenti

- Creare VM con disco su `ceph-vm`; live migrate senza copiare il disco tra nodi.
- Aggiungere la VM a HA come descritto in [proxmox.md](proxmox.md).
- Spegnere un nodo: osservare degradazione e quorum; riaccenderlo e attendere
  recovery completa. Con due nodi persi si perde il quorum; non abbassare min_size.
- Confrontare traffico su `vmbr0` e `vmbr1` usando `ip -s link`.
- Nel lab backup, verificare che PBS/backup usino vmbr0 e non la rete Ceph vmbr1.
