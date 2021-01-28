From ubuntu:20.04

#Maintainer is deprecated 
LABEL authors="seweryn.sitarski@p.lodz.pl"

# W celu eliminacji bledu "debconf: unable to initialize frontend: Dialog"
ENV DEBIAN_FRONTEND noninteractive

# Base tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    openssh-server \
    vim \
    coreutils \
    less \
    git

# Network tools
RUN apt-get install -y --no-install-recommends \
    isc-dhcp-client \
    ifenslave \
    vlan \
    wget

# MooseFS
RUN apt-get install -y --no-install-recommends gnupg fuse3 && \
    wget --no-check-certificate -O - https://ppa.moosefs.com/moosefs.key | apt-key add - && \
    echo "deb http://ppa.moosefs.com/moosefs-3/apt/ubuntu/focal focal main" > /etc/apt/sources.list.d/moosefs.list && \
    apt update && \
    apt install moosefs-pro-client

# Na potrzeby projektu bocm
# Disk tools
RUN apt-get install -y --no-install-recommends \  
    gdisk \
    lvm2 \
    xfsprogs \
    dosfstools \
    parted
# Other
RUN apt-get install -y --no-install-recommends \
    initramfs-tools

#CMD cd /home/Projekty/conf; ./mntconf; cd /home/Projekty/; /bin/bash; cd /home/Projekty/conf; ./umntconf
#CMD /bin/bash