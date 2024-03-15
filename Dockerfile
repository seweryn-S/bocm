FROM ubuntu:20.04

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
RUN apt-get update; apt-get install -y --no-install-recommends \
    openssh-server \
    vim \
    zstd \
    coreutils \
    policykit-1 \
    less \
    dropbear-initramfs

# Disk tools
RUN apt-get install -y --no-install-recommends \  
    gdisk lvm2 xfsprogs dosfstools parted 

# Network tools
RUN apt-get install -y --no-install-recommends \
    isc-dhcp-client \
    ifenslave \
    vlan \
    wget

# PCI tools
RUN apt-get install -y --no-install-recommends \
    pciutils

# Install Rclone, oraz niezbenych narzedzi
# // TODO: Dopisac kompilację i optymalizację. Wycięcie niepotrzebnych chmur i komend.
ENV RCLONE_VER=v1.56.0
RUN apt-get install -y unzip pv && \
    wget --no-check-certificate https://downloads.rclone.org/${RCLONE_VER}/rclone-${RCLONE_VER}-linux-amd64.zip && \
    unzip rclone-${RCLONE_VER}-linux-amd64.zip && mv rclone-${RCLONE_VER}-linux-amd64 rclone

# Disk_info
RUN cd /usr/local/sbin/; wget --no-check-certificate https://raw.githubusercontent.com/bockpl/ubuntu18.04src/master/bin/disk_info; chmod +x disk_info; cd /

# Dropbear configuration
ADD etc/dropbear-initramfs/config /etc/dropbear-initramfs/
ADD etc/dropbear-initramfs/authorized_keys /etc/dropbear-initramfs/
RUN chmod 600 /etc/dropbear-initramfs/authorized_keys