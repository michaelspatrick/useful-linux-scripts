#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Check for IP argument
if [ -z "$1" ]; then
    echo "Usage: $0 <IP_ADDRESS>"
    exit 1
fi

IP="$1"
echo "🧹 Unblocking IP: $IP"

# Check if firewalld is active
if systemctl is-active --quiet firewalld; then
    echo "🔥 Firewalld detected, removing rich rule..."
    firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='$IP' reject"
    firewall-cmd --reload
    echo "✅ IP $IP unblocked via firewalld"
    exit 0
fi

# Fallback to iptables
if command -v iptables &> /dev/null; then
    echo "🛡 Using iptables to unblock IP"
    iptables -D INPUT -s "$IP" -j DROP

    if [ -f /etc/sysconfig/iptables ]; then
        echo "💾 Saving iptables rules to /etc/sysconfig/iptables..."
        iptables-save > /etc/sysconfig/iptables
        echo "✅ IP $IP unblocked and rules saved"
    else
        echo "⚠️ Warning: /etc/sysconfig/iptables not found. Install iptables-services to persist rules."
    fi

    exit 0
else
    echo "❌ Neither iptables nor firewalld found. Cannot unblock IP."
    exit 1
fi

