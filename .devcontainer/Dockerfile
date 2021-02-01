FROM ubuntu:20.04

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
    wget \
    ca-certificates \
    git

# Bash language server
RUN apt-get update && \
    apt-get install -y nodejs npm && \
    npm i -g bash-language-server

# MooseFS
RUN apt-get update && \
    apt-get install -y --no-install-recommends gnupg fuse3 && \
    wget --no-check-certificate -O - https://ppa.moosefs.com/moosefs.key | apt-key add - && \
    echo "deb http://ppa.moosefs.com/moosefs-3/apt/ubuntu/focal focal main" > /etc/apt/sources.list.d/moosefs.list && \
    apt update && \
    apt install moosefs-pro-client

# Na potrzeby projektu bocm
# Disk tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \  
    gdisk \
    lvm2 \
    xfsprogs \
    dosfstools \
    parted
# Network tools
RUN apt-get install -y --no-install-recommends \
    isc-dhcp-client \
    ifenslave \
    vlan
# Other
RUN apt-get install -y --no-install-recommends \
    linux-image-generic \
    initramfs-tools \
    gdisk \
    lvm2 \
    xfsprogs \
    dosfstools \
    parted
# Install Rclone, oraz niezbenych narzedzi
# // TODO: Dopisac kompilację i optymalizację. Wycięcie niepotrzebnych chmur i komend.
RUN apt-get install -y unzip pv && \
    wget --no-check-certificate https://downloads.rclone.org/v1.53.3/rclone-v1.53.3-linux-amd64.zip && \
    unzip rclone-v1.53.3-linux-amd64.zip && mv rclone-v1.53.3-linux-amd64 rclone
# Disk_info
RUN cd /usr/local/sbin/; wget --no-check-certificate https://raw.githubusercontent.com/bockpl/ubuntu18.04src/master/bin/disk_info; chmod +x disk_info; cd /

ADD .devcontainer/bootstrap.sh /bootstrap.sh

ENTRYPOINT ["/bin/bash", "/bootstrap.sh"]

#CMD cd /home/Projekty/conf; ./mntconf; cd /home/Projekty/; /bin/bash; cd /home/Projekty/conf; ./umntconf
#CMD /bin/bash