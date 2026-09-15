# Dischi

Le capacità sono dichiarate in `../lab.json` e `../Vagrantfile`.
Vagrant/VirtualBox gestiscono i file nella directory macchina del provider:
questa cartella è riservata a eventuali dischi/import manuali, esclusi da Git.
Non spostare i VDI registrati manualmente. `vagrant destroy` elimina i dischi
gestiti dal provider, inclusi OSD/datastore e VM annidate. `halt` li conserva.
