# Codex

Codex legge `AGENTS.md` dalla radice del repository. Aprire questa directory come
workspace. Non sono necessari MCP, plugin o impostazioni globali aggiuntive.

Il catalogo aggiornato degli undici laboratori è nel README globale. Ogni cartella
deve restare condivisibile autonomamente e contenere:

- `Vagrantfile`, percorso assistito;
- `Vagrant.start`, percorso basic senza provisioning guest;
- `README.md`, topologia e uso dei due percorsi;
- `STEPS.md`, ricostruzione manuale da OS pulito, portabile su VM o bare metal.

Nel percorso basic usare sempre `VAGRANT_VAGRANTFILE=Vagrant.start`. Non
alternarlo al Vagrantfile assistito sulle stesse istanze.

Richieste utili:
- «Valida staticamente tutti i laboratori e correggi gli errori».
- «Aggiungi un laboratorio seguendo docs/architecture.md».
- «Rivedi il provisioning senza eseguirlo sull'host».
- «Verifica che STEPS.md permetta di ricreare il lab da zero fuori da Vagrant».

Non memorizzare token o credenziali in questa cartella.
