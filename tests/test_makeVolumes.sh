#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 Seweryn Sitarski
# Author: Seweryn Sitarski
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3,
# as published by the Free Software Foundation.
# See the LICENSE file for details.


#!/usr/bin/env bash

onExit() {
  popd
}
trap onExit SIGQUIT
pushd $(pwd)
cd $(dirname $0)

BOCMDIR="../etc/bocm"

source ${BOCMDIR}/functions.sh

DEV=$1
if [ "x$DEV" == "x" ]; then
  DEV=/dev/sdb
fi
echo $DEV
#export DEBUG=sym
_result=$(cleanDisk ${DEV})
makeStdPartition ${DEV} "${BOCMDIR}/partitions.yml"
#set -x
makeVolumes ${DEV} "${BOCMDIR}/partitions.yml"
#echo ${_result}