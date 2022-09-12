#!/bin/bash
#
# Removes bans of all listed countries via iptables and ipset.
# Based upon IP sets from https://www.ipdeny.com/ipblocks/
#

COUNTRIES=('cn' 'ru' 'iq' 'ir')

iptables -v -F blocked_countries

for i in "${COUNTRIES[@]}"; do
    echo "Unban country ${i}"
    ipset flush "countries_${i}"
done
