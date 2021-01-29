#!/bin/bash

for HOST in cmi10 botest-adm; do
  if ! [ -d /mnt/${HOST} ]; then
    mkdir -p /mnt/${HOST}
  fi
  mfsmount -H mfsmaster.dev.p.lodz.pl -S /obrazy/KOPL/CONFIGS/${HOST} /mnt/${HOST}
done