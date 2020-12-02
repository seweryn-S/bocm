From ubuntu:18.04

#Maintainer is deprecated 
LABEL authors="seweryn.sitarski@p.lodz.pl"

# W celu eliminacji bledu "debconf: unable to initialize frontend: Dialog"
ENV DEBIAN_FRONTEND noninteractive

# Aktualizacja podstawowego obrazu oraz czyszczenie
#RUN set -xe \
RUN apt -y update && \
    apt -y install initramfs-tools && \
    apt -y install linux-image-generic

# Base tools
RUN apt-get install -y --no-install-recommends \
    openssh-server \
    vim \
    coreutils \
    policykit-1 

# Disk tools
RUN apt-get install -y --no-install-recommends \  
    gdisk lvm2 xfsprogs dosfstools parted 

# Network tools
RUN apt-get install -y --no-install-recommends \
    isc-dhcp-client \
    ifenslave \
    vlan \
    wget

# Disk_info
RUN cd /usr/local/sbin/; wget --no-check-certificate https://raw.githubusercontent.com/bockpl/ubuntu18.04src/master/bin/disk_info; chmod +x disk_info; cd /
