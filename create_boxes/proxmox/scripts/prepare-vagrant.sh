#!/usr/bin/env bash
# Prepara l'accesso richiesto da Vagrant senza configurare rete o cluster del lab.
set -euo pipefail

[[ $EUID == 0 ]] || { echo 'Questo script deve essere eseguito da root.' >&2; exit 1; }
[[ -s /tmp/vagrant-insecure.pub ]] || {
  echo 'Chiave pubblica Vagrant non caricata da Packer.' >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive

# L'ISO abilita per default i repository enterprise PVE e Ceph, che richiedono
# una subscription. Disabilitarli prima del primo apt-get update evita errori
# 401; la box di laboratorio abilita poi soltanto pve-no-subscription.
for file in /etc/apt/sources.list.d/*; do
  [[ -f $file ]] || continue
  if grep -qF 'enterprise.proxmox.com' "$file"; then
    mv "$file" "$file.disabled"
  fi
done
cat > /etc/apt/sources.list.d/infra-pve.list <<'EOF'
deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription
EOF

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl openssh-server sudo

if ! id vagrant >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --user-group vagrant
fi
install -d -o vagrant -g vagrant -m 0700 /home/vagrant/.ssh
install -o vagrant -g vagrant -m 0600 \
  /tmp/vagrant-insecure.pub /home/vagrant/.ssh/authorized_keys
install -m 0440 /dev/stdin /etc/sudoers.d/vagrant <<'EOF'
vagrant ALL=(ALL) NOPASSWD: ALL
EOF

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/90-vagrant-box.conf <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication yes
UseDNS no
EOF
sshd -t
systemctl enable ssh

# watchdog-mux arma softdog a 10 s per il fencing HA. In VirtualBox il guest
# può restare congelato più a lungo (import, catch-up del clock, pause del
# host) e si resetterebbe da solo nel primo minuto di vita del clone, prima di
# qualsiasi provisioning. La box è solo VirtualBox: registrare l'evento invece
# di riavviare. I lab lo ripetono in finalize-pve.sh per le box già costruite.
cat > /etc/modprobe.d/infra-lab-softdog.conf <<'EOF'
options softdog soft_noboot=1
EOF

cat > /etc/infra-box-release <<EOF
NAME=local/proxmox-ve-9.2
BOX_VERSION=${BOX_VERSION:?BOX_VERSION non impostata da Packer}
PVE_TEMPLATE_HOSTNAME=proxmox-template
EOF

# Rigenera le identità proprie del clone prima che SSH accetti connessioni.
cat > /usr/local/sbin/infra-box-firstboot <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
systemd-machine-id-setup
ssh-keygen -A
rm -f /var/lib/infra-box/firstboot
systemctl disable infra-box-firstboot.service
EOF
chmod 0755 /usr/local/sbin/infra-box-firstboot

cat > /etc/systemd/system/infra-box-firstboot.service <<'EOF'
[Unit]
Description=Rigenera le identita uniche del clone Vagrant
ConditionPathExists=/var/lib/infra-box/firstboot
DefaultDependencies=no
After=local-fs.target
Before=ssh.service pve-cluster.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/infra-box-firstboot

[Install]
WantedBy=multi-user.target
EOF
systemctl enable infra-box-firstboot.service

rm -f /tmp/vagrant-insecure.pub
