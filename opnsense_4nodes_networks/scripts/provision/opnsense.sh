#!/bin/sh
# Converte la box FreeBSD in OPNsense con il metodo ufficiale opnsense-bootstrap
# e scrive una config.xml minima ricavata da lab.json: interfacce, accesso SSH
# per Vagrant e poche regole di partenza. Il resto è l'esercizio di STEPS.md.
# Riferimento: https://github.com/opnsense/update (opnsense-bootstrap) e
# https://github.com/punktDe/vagrant-opnsense per l'integrazione con Vagrant.
set -eu
name=$1 release=$2 lan_address=$3 lan_mac=$4 segments=$5
[ "$(id -u)" = 0 ] || { echo 'Serve root' >&2; exit 1; }
[ "$(uname -s)" = FreeBSD ] || { echo 'Serve la box FreeBSD' >&2; exit 1; }
config=/usr/local/etc/config.xml
work=/tmp/opnsense-lab

if_for_mac() {
  for iface in $(ifconfig -l ether); do
    if [ "$(ifconfig "$iface" | awk '/ether/ {print $2}')" = "$1" ]; then
      echo "$iface"
      return 0
    fi
  done
  echo "NIC con MAC $1 assente" >&2
  return 1
}
# La NIC NAT è quella con la default route: diventa la WAN di OPNsense.
wan_if=$(route -n get default | awk '/interface:/ {print $2}')
lan_if=$(if_for_mac "$lan_mac")

mkdir -p "$work"
if [ ! -f /usr/local/opnsense/version/core ]; then
  fetch -o "$work/opnsense-bootstrap.sh" \
    https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in
  # Il riavvio finale viene tolto: la config.xml va scritta prima del reboot.
  sed -i '' -e '/^[[:space:]]*reboot$/d' "$work/opnsense-bootstrap.sh"
  # "pkg unlock -ya" fallisce con alcune versioni di pkg (freebsd/pkg#2278);
  # la box non ha pacchetti bloccati, quindi il passo si può saltare.
  sed -i '' -e '/pkg unlock -ya/d' "$work/opnsense-bootstrap.sh"
  sh "$work/opnsense-bootstrap.sh" -r "$release" -y
fi

# Hash root di default preso dalla config installata dal bootstrap: nessuna
# password nel repository. Il wizard chiede di cambiarla al primo accesso.
root_hash=$(sed -n 's/.*<password>\(\$[^<]*\)<\/password>.*/\1/p' "$config" | head -n 1)
[ -n "$root_hash" ] || { echo 'Hash root non trovato nella config di default' >&2; exit 1; }
vagrant_key=$(b64encode -r dummy < /home/vagrant/.ssh/authorized_keys | tr -d '\n')

opt_interfaces=""
opt_rules=""
n=0
old_ifs=$IFS
IFS=';'
for segment in $segments; do
  IFS=$old_ifs
  n=$((n + 1))
  seg_name=${segment%%,*}
  rest=${segment#*,}
  seg_mac=${rest%%,*}
  seg_ip=${rest#*,}
  seg_if=$(if_for_mac "$seg_mac")
  seg_upper=$(echo "$seg_name" | tr '[:lower:]' '[:upper:]')
  opt_interfaces="$opt_interfaces
    <opt$n>
      <enable>1</enable>
      <if>$seg_if</if>
      <descr>$seg_upper</descr>
      <ipaddr>$seg_ip</ipaddr>
      <subnet>24</subnet>
      <media/>
      <mediaopt/>
    </opt$n>"
  # Solo dmz parte senza regole: i suoi flussi in uscita sono bloccati finché
  # l'esercizio non li autorizza. Gli altri segmenti partono aperti.
  if [ "$seg_name" != dmz ]; then
    opt_rules="$opt_rules
    <rule>
      <type>pass</type>
      <ipprotocol>inet</ipprotocol>
      <descr>Lab: allow $seg_upper to any</descr>
      <interface>opt$n</interface>
      <source>
        <network>opt$n</network>
      </source>
      <destination>
        <any/>
      </destination>
    </rule>"
  fi
  IFS=';'
done
IFS=$old_ifs

cat > "$config" <<XML
<?xml version="1.0"?>
<opnsense>
  <trigger_initial_wizard/>
  <theme>opnsense</theme>
  <system>
    <optimization>normal</optimization>
    <hostname>$name</hostname>
    <domain>lab.internal</domain>
    <dnsallowoverride>1</dnsallowoverride>
    <dnsallowoverride_exclude/>
    <group>
      <name>admins</name>
      <description>System Administrators</description>
      <scope>system</scope>
      <gid>1999</gid>
      <member>0</member>
      <member>1001</member>
      <priv>page-all</priv>
    </group>
    <user>
      <name>root</name>
      <descr>System Administrator</descr>
      <scope>system</scope>
      <groupname>admins</groupname>
      <password>$root_hash</password>
      <uid>0</uid>
    </user>
    <user>
      <name>vagrant</name>
      <descr>Vagrant</descr>
      <scope>system</scope>
      <groupname>admins</groupname>
      <password>*</password>
      <uid>1001</uid>
      <shell>/bin/sh</shell>
      <authorizedkeys>$vagrant_key</authorizedkeys>
    </user>
    <timezone>Etc/UTC</timezone>
    <timeservers>0.opnsense.pool.ntp.org 1.opnsense.pool.ntp.org 2.opnsense.pool.ntp.org 3.opnsense.pool.ntp.org</timeservers>
    <webgui>
      <protocol>https</protocol>
    </webgui>
    <disablenatreflection>yes</disablenatreflection>
    <usevirtualterminal>1</usevirtualterminal>
    <disableconsolemenu/>
    <powerd_ac_mode>hadp</powerd_ac_mode>
    <powerd_battery_mode>hadp</powerd_battery_mode>
    <powerd_normal_mode>hadp</powerd_normal_mode>
    <bogons>
      <interval>monthly</interval>
    </bogons>
    <pf_share_forward>1</pf_share_forward>
    <lb_use_sticky>1</lb_use_sticky>
    <ssh>
      <enabled>enabled</enabled>
      <group>admins</group>
    </ssh>
    <sudo_allow_wheel>2</sudo_allow_wheel>
    <sudo_allow_group>admins</sudo_allow_group>
    <rrdbackup>-1</rrdbackup>
    <netflowbackup>-1</netflowbackup>
  </system>
  <interfaces>
    <wan>
      <enable>1</enable>
      <if>$wan_if</if>
      <descr>WAN</descr>
      <mtu/>
      <ipaddr>dhcp</ipaddr>
      <subnet/>
      <gateway/>
      <dhcphostname/>
      <media/>
      <mediaopt/>
    </wan>
    <lan>
      <enable>1</enable>
      <if>$lan_if</if>
      <descr>MGMT</descr>
      <ipaddr>$lan_address</ipaddr>
      <subnet>24</subnet>
      <media/>
      <mediaopt/>
    </lan>$opt_interfaces
  </interfaces>
  <unbound>
    <enable>1</enable>
  </unbound>
  <nat>
    <outbound>
      <mode>automatic</mode>
    </outbound>
  </nat>
  <filter>
    <rule>
      <type>pass</type>
      <ipprotocol>inet</ipprotocol>
      <descr>Lab: Vagrant SSH on WAN</descr>
      <interface>wan</interface>
      <protocol>tcp</protocol>
      <source>
        <any>1</any>
      </source>
      <destination>
        <network>wanip</network>
        <port>22</port>
      </destination>
    </rule>
    <rule>
      <type>pass</type>
      <ipprotocol>inet</ipprotocol>
      <descr>Default allow LAN to any rule</descr>
      <interface>lan</interface>
      <source>
        <network>lan</network>
      </source>
      <destination>
        <any/>
      </destination>
    </rule>$opt_rules
  </filter>
  <rrd>
    <enable/>
  </rrd>
  <ntpd>
    <prefer>0.opnsense.pool.ntp.org</prefer>
    <ispool>0.opnsense.pool.ntp.org 1.opnsense.pool.ntp.org 2.opnsense.pool.ntp.org 3.opnsense.pool.ntp.org</ispool>
  </ntpd>
</opnsense>
XML
chmod 0600 "$config"

# sudoers della box Bento: OPNsense rigenera il proprio dalla config.xml, ma il
# file locale resta e va riferito all'utente perché il gruppo vagrant sparisce.
[ -f /usr/local/etc/sudoers.d/vagrant ] && sed -i '' -e 's/^%//' /usr/local/etc/sudoers.d/vagrant

echo "OPNsense $release installato: riavvio fra 10 secondi. GUI su https://$lan_address"
# Riavvio in background: il provisioner termina con successo e Vagrant non
# interpreta la chiusura di SSH come errore.
nohup sh -c 'sleep 10; /sbin/reboot' >/dev/null 2>&1 &
