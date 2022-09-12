#!/bin/bash
#
# Cron entry: @reboot /bin/sleep 60 ; /bin/bash -c ". /home/centos/.bashrc ; /home/centos/whitelist-firewall.sh"
#
# Based upon: https://linux-audit.com/blocking-ip-addresses-in-linux-with-iptables/
# Reads a file of IP addresses and adds them to the whitelist
#
# Initial Setup
# Create whitelist with ipset utility (once)
# sudo ipset create whitelist hash:ip hashsize 4096
# sudo iptables -I INPUT -m set --match-set whitelist src -j ACCEPT
# sudo iptables -I FORWARD -m set --match-set whitelist src -j ACCEPT
#

IPFILE="/home/centos/IPs-whitelist.txt"

for IP in $(cat $IPFILE)
do
  echo "Whitelisting $IP"
  ipset add whitelist $IP
done
