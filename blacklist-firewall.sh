#!/bin/bash
#
# Based upon: https://linux-audit.com/blocking-ip-addresses-in-linux-with-iptables/
# Reads a file of IP addresses to permanently ban and then bans each one
#
# Initial Setup
# Create blacklist with ipset utility (once)
# sudo ipset create blacklist hash:ip hashsize 4096
# sudo iptables -I INPUT -m set --match-set blacklist src -j DROP
# sudo iptables -I FORWARD -m set --match-set blacklist src -j DROP
#

IPFILE="/home/centos/IPs-banned.txt"

for IP in $(cat $IPFILE)
do
  echo "Banning $IP"
  ipset add blacklist $IP
done
