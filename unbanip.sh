#!/bin/bash
# Script to unban an IP via fail2ban jails

if [[ $# -eq 0 ]] ; then
    echo "usage: $0 <ip-to-unban> <jail-name>"
    exit 0
fi

echo -n "Current IP ban status: "
if [ 0 -lt `sudo iptables -n -L|grep "REJECT"|grep "$ip"|wc -l` ]; then
  echo "BANNED"
else
  echo "NOT BANNED"
  exit
fi

echo -n "Checking that jail exists: "
exists=`sudo fail2ban-client status|grep "$jail"`
if [ 0 -lt ${#exists} ]; then
  echo "EXISTS"
else
  echo "DOES NOT EXIST"
  exit
fi

echo "Unbanning ip, $1, from jail, $2."
sudo fail2ban-client set $2 unbanip $1
