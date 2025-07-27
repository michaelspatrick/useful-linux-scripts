#!/bin/bash
#
# List all IPs for failed logins which may be break-in attempts.
# Script is useful to send to get IPs to add to the text file for blacklist-firewall.sh
#

sudo cat /var/log/secure | grep BREAK-IN | grep -Po '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort | uniq
