#!/bin/bash

sed -i 's|/swap|#/swap|' /etc/fstab
sed -i 's|GRUB_CMDLINE_LINUX=""|GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"|' /etc/default/grub

apt-get update && apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    net-tools \
    python3-pip \
    git \
    software-properties-common -y

# Prevent conflicts between docker iptables (packet filtering) rules and k8s pod communication
# See https://github.com/kubernetes/kubernetes/issues/40182 for further details.
iptables -P FORWARD ACCEPT

# disable swap
sed -i '/swap/d' /etc/fstab
swapoff -a

# Update hosts file
echo "Update /etc/hosts file"
cat >>/etc/hosts<<EOF
192.168.10.10 node-1.k8s.com node-1
192.168.10.11 node-2.k8s.com node-2
192.168.10.12 node-3.k8s.com node-2
EOF
