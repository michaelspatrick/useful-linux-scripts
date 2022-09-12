#!/bin/bash
#
# Cron entry: @reboot /bin/sleep 40 ; /bin/bash -c ". /home/centos/.bashrc ; /home/centos/country-firewall.sh"
#
# Initial Setup
# sudo yum -y install ipset
# sudo iptables -N blocked_countries
# sudo iptables -I INPUT -j blocked_countries -m comment --comment "Blocked countries"
# sudo iptables -I FORWARD -j blocked_countries -m comment --comment "Blocked countries"
#
# Check Status
# iptables -v -n -L blocked_countries
#

COUNTRIES=('cn' 'ru' 'iq' 'ir')

for COUNTRY in "${COUNTRIES[@]}"; do
    ipset create "countries_${COUNTRY}" hash:net
done

iptables -v -F blocked_countries

for i in "${COUNTRIES[@]}"; do
    echo "Ban IP of country ${i}"
    ipset flush "countries_${i}"

    for IP in $(wget --no-check-certificate -O - https://www.ipdeny.com/ipblocks/data/countries/${i}.zone)
    do
        ipset add "countries_${i}" $IP
    done
    iptables -I blocked_countries   -m set --match-set "countries_${i}" src  -j DROP -m comment   --comment "Block .${i}"
done
