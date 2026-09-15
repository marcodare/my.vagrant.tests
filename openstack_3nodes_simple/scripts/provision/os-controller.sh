#!/usr/bin/env bash
set -euo pipefail
[[ $(cat /var/lib/infra-lab/role) == os-controller ]] || exit 1
# Tool di deployment isolati nel guest Ubuntu 24.04; non usa il Python dell'host.
if [[ ! -d /opt/kolla-venv ]]; then python3 -m venv /opt/kolla-venv; fi
/opt/kolla-venv/bin/pip install 'kolla-ansible==21.3.0' 'python-openstackclient<9'
install -d -o vagrant -g vagrant -m 0700 /etc/kolla
if [[ ! -f /etc/kolla/passwords.yml ]]; then
  install -o vagrant -g vagrant -m 0600 /opt/kolla-venv/share/kolla-ansible/etc_examples/kolla/passwords.yml /etc/kolla/passwords.yml
fi
install -o vagrant -g vagrant -m 0644 /home/vagrant/infra-kolla/globals.yml /etc/kolla/globals.yml
chown -R vagrant:vagrant /home/vagrant/infra-kolla
echo 'Tool installati. Configurare SSH e lanciare Kolla manualmente dal README.'
