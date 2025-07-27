#!/bin/bash
#
# Cron entry: @reboot /bin/sleep 60 ; /bin/bash -c ". /home/centos/.bashrc ; /home/centos/blacklist-firewall.sh"
#
# Based upon: https://linux-audit.com/blocking-ip-addresses-in-linux-with-iptables/
# Reads a file of IP addresses to permanently ban and then bans each one.
# File contains one IP address per line.
#
# Initial Setup
# Create blacklist with ipset utility (once)
# sudo ipset create blacklist hash:ip hashsize 4096
# sudo iptables -I INPUT -m set --match-set blacklist src -j DROP
# sudo iptables -I FORWARD -m set --match-set blacklist src -j DROP
#

if [[ -z $1 ]]; then
  IPFILE="/etc/firewall/custom.list"

  for IP in $(cat $IPFILE)
  do
    echo "Banning $IP"
    ipset add blacklist $IP
  done
else
  echo "Banning $1"
  ipset add blacklist $1
fi
