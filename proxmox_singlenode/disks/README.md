# Dischi

Il disco OS da 80 GB è dichiarato in `../lab.json` e `../Vagrantfile` ed è
gestito da Vagrant/VirtualBox nella directory della VM. Questa cartella è
riservata a import manuali esclusi da Git. `vagrant halt` conserva i dischi;
`vagrant destroy` elimina quelli gestiti dal provider e i guest annidati.
