#!/bin/bash
#
# Add IPs for failed logins which may be break-in attempts to a text file and ensure no duplicates.
# This file can then be imported into a blacklist.
#

LISTFILE="/etc/firewall/custom.list"
TMPFILE="/tmp/failed-logins.txt"

cat ${LISTFILE} > ${TMPFILE}
cat /var/log/secure | grep BREAK-IN | grep -Po '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' >> ${TMPFILE}
cat /var/log/fail2ban.log | grep sshd | grep -Po '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' >> ${TMPFILE}
cat $TMPFILE | sort | uniq > ${LISTFILE}
