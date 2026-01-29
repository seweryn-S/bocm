#!/usr/bin/env bash

# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Seweryn Sitarski
# Author: Seweryn Sitarski
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3,
# as published by the Free Software Foundation.
# See the LICENSE file for details.

# shellcheck disable=SC2154
# shellcheck disable=SC1091

# Configure
BASEDIR=../etc/bocm

onExit() {
  popd
}
trap onExit SIGQUIT
pushd $(pwd)
cd $(dirname $0)

set -e
source ${BASEDIR}/bash-yaml/script/yaml.sh

parse_yaml ${BASEDIR}/partitions.yml
create_variables ${BASEDIR}/partitions.yml

#echo il_part=${#part__number[@]}
#echo il_vol=${#vol__part[@]}

printf '\n%s\n' "Analiza zmiennych"
for (( i=0; i<${#partition__number[@]}; i++ )); do
  echo part: ${partition__number[i]}
  for (( v=0; v<${#volume__part[@]}; v++ )); do
    if [[ ${volume__part[$v]} = ${partition__number[i]} ]]; then
      echo "part_vol_name: ${volume__name[$v]}"
      echo "  part_vol_dev: ${volume__dev[$v]}"
      echo "  part_vol_fstype: ${volume__fstype[$v]}"
      echo "  part_vol_size: ${volume__size[$v]}"
      echo "  part_vol_mnt: ${volume__mnt[$v]}"
      echo "  part_vol_mntopt: ${volume__mntopt[$v]}"
      echo "  part_vol_raid: ${volume__raid[$v]}"
      echo "  part_vol_type: ${volume__type[$v]}"
    fi
  done
done

#echo Ilosc_partycji=${#partition__number[@]}
#echo Ilosc_vol=${#partition__volume__number[@]}

# Execute
#create_variables file.yml

#echo ${partition}
#len=${#partition__number[@]}
#echo LEN ${len}
#for (( vol=0; vol<${#partition__number[@]}; vol++ )); do
#  echo ${partition__number[${vol}]} ${partition__name[${vol}]} ${partition__volname[${vol}]} ${partition__mntpoint[${vol}]} \
#${partition__size[${vol}]} ${partition__fstype[${vol}]} ${partition__raid[${vol}]}
#done