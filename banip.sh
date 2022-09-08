#!/bin/bash
# Script works with fail2ban to ban and IP address via a jail

if [[ $# -eq 0 ]] ; then
    echo "usage: $0 <ip-to-ban> <jail-name>"
    exit 0
fi

echo -n "Current IP ban status: "
if [ 0 -lt `sudo iptables -n -L|grep "REJECT"|grep "$ip"|wc -l` ]; then
  echo "BANNED"
  exit
else
  echo "NOT BANNED"
fi

echo -n "Checking that jail exists: "
exists=`sudo fail2ban-client status|grep "$jail"`
if [ 0 -lt ${#exists} ]; then
  echo "EXISTS"
else
  echo "DOES NOT EXIST"
  exit
fi

echo "Banning ip, $1, via jail, $2."
sudo fail2ban-client set $2 banip $1
