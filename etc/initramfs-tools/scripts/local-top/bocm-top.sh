#!/bin/sh

# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Seweryn Sitarski
# Author: Seweryn Sitarski
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3,
# as published by the Free Software Foundation.
# See the LICENSE file for details.


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
configure_networking
log_end_msg

# Wpis w /etc/hosts dla adresu boipxe, potrzebne z powodu SSL-a
log_begin_msg "Setting boipxe address"
  echo ""
  # Ustaw maksymalną liczbę prób odczytu pliku lease
  MAX_ATTEMPTS=30
  ATTEMPT=1

  # Poczekaj, aż plik lease będzie zawierał 'dhcp-server-identifier'
  DHCP_SERVER=""
  while [ -z "${DHCP_SERVER}" ] && [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; do
    echo "Step: ${ATTEMPT}/${MAX_ATTEMPTS}: Waiting for DHCP..."
    DHCP_SERVER="$(awk '/dhcp-server-identifier/ { print $3 }' /var/lib/dhcp/dhclient.leases | sed -e 's/;//')"
    ATTEMPT=$((ATTEMPT+1))
    sleep 1
  done
  if [ -z "${DHCP_SERVER}" ]; then
    panic "Failed to obtain DHCP server address after ${MAX_ATTEMPTS} attempts."
  else
    echo "${DHCP_SERVER} boipxe" > /etc/hosts
  fi
log_end_msg

maybe_break after_net_config

bin/bash -c ". /scripts/functions; . ./${BOCMDIR}/functions.sh; ssh_config;"

# Nadpisywanie plikow initramfs-u z katalogu konfiguracyjnego
bin/bash -c ". /scripts/functions; . ./${BOCMDIR}/functions.sh; override_initrd_scripts;"
# Tu korzystamy z juz nadpisanych skryptow i funkcji
maybe_break before_bocm_top
bin/bash -c ". /scripts/functions; . ./${BOCMDIR}/functions.sh; bocm_top;"

exit 0
