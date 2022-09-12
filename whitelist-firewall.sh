#!/bin/bash
#
# Cron entry: @reboot /bin/sleep 60 ; /bin/bash -c ". /home/centos/.bashrc ; /home/centos/whitelist-firewall.sh"
#
# Based upon: https://bobcares.com/blog/iptables-whitelist-ip/
# Reads a file of IP addresses to whitelist
#

IPFILE="/home/centos/IPs-whitelist.txt"

for IP in $(cat $IPFILE)
do
  echo "Whitelisting $IP"
  iptables -A INPUT -s $IP -j ACCEPT
done
