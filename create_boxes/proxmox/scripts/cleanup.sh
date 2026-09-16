#!/usr/bin/env bash
# Rimuove identità e residui del builder prima dell'export della box.
set -euo pipefail

[[ $EUID == 0 ]] || { echo 'Questo script deve essere eseguito da root.' >&2; exit 1; }

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
find /var/log -type f -exec truncate -s 0 {} +
rm -f /root/.bash_history /home/vagrant/.bash_history

# La password root esiste solo per il communicator Packer. Dopo il packaging si
# entra come vagrant e si imposta una password root specifica del laboratorio.
passwd --lock root
sed -i 's/^PasswordAuthentication yes$/PasswordAuthentication no/' \
  /etc/ssh/sshd_config.d/90-vagrant-box.conf

# Validare la configurazione mentre le chiavi del builder esistono ancora:
# `sshd -t` fallirebbe dopo la loro rimozione, anche se la configurazione fosse
# corretta. Le nuove chiavi vengono create dal servizio firstboot del clone.
sshd -t

# I cloni non devono condividere machine-id né chiavi host SSH. Il servizio
# infra-box-firstboot le rigenera prima dell'avvio di ssh e pve-cluster.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id /etc/ssh/ssh_host_*
install -d -m 0755 /var/lib/infra-box
touch /var/lib/infra-box/firstboot

sync
