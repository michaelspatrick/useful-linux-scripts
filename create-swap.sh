#!/bin/sh
# Script creates a swapfile at a specified location and size.  
# It then sets designated swappiness value and makes it persistent.

if [[ $# -eq 0 ]] ; then
    echo "usage: $0 <path-to-new-swap-file> <size-in-megabytes> <swappiness>"
    echo "example: $0 /swap 4096 10"
    exit 0
fi

sudo dd if=/dev/zero of=$1 bs=1M count=$2
sudo chmod 600 $1
sudo mkswap $1
sudo swapon $1
sudo sh -c "echo '$1 swap swap defaults 0 0' >> /etc/fstab"
sudo sysctl vm.swappiness=$3
sudo sh -c "echo 'vm.swappiness=$3' >> /etc/sysctl.conf"
sudo swapon --show
