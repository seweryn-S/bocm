#!/bin/sh

PREREQ=""

prereqs() {
  echo "$PREREQ"
}
case $1 in
prereqs)
  prereqs
  exit 0
  ;;
esac

# Begin real processing below this line
. /scripts/functions

# Jezeli nie jest zdefiniowany szablon na MFS i nie jest to start z iPXE http to nic nie rob
if [ "x${IMG_URI}" = "x" ]; then
  exit 0
fi

# from /usr/share/initramfs-tools/scripts/nfs
#	modprobe nfs
# For DHCP
modprobe af_packet

#wait_for_udev 10
udevadm settle

maybe_break before_net_config

log_begin_msg "Configuring networking"
# Nadpisanie oryginalnej konfiguracji DHCP wlasna bez pobierania adresow DNS
mv /etc/custom-dhclient.conf /etc/dhcp/dhclient.conf

configure_networking
log_end_msg

# Ustawienie zawsze serwera DNS na adres serwera dhcp, potrzebne z powodu SSL-a
log_begin_msg "Overriding resolv.conf"
  sleep 2
  DHCP_SERVER="$(awk '/dhcp-server-identifier/ { print $3 }' /var/lib/dhcp/dhclient.leases | sed -e 's/;//')"
  echo "nameserver ${DHCP_SERVER}" > /etc/resolv.conf
log_end_msg

maybe_break after_net_config

bin/bash -c ". /scripts/functions; . ./${BOCMDIR}/functions.sh; ssh_config;"

# Nadpisywanie plikow initramfs-u z katalogu konfiguracyjnego
bin/bash -c ". /scripts/functions; . ./${BOCMDIR}/functions.sh; override_initrd_scripts;"
# Tu korzystamy z juz nadpisanych skryptow i funkcji
maybe_break before_bocm_top
bin/bash -c ". /scripts/functions; . ./${BOCMDIR}/functions.sh; bocm_top;"

exit 0
