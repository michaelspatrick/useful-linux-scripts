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
echo "🚫 Blocking IP: $IP"

# Check if firewalld is active
if systemctl is-active --quiet firewalld; then
    echo "🔥 Firewalld detected, adding rich rule..."
    firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$IP' reject"
    firewall-cmd --reload
    echo "✅ IP $IP blocked via firewalld"
    exit 0
fi

# Fallback to iptables
if command -v iptables &> /dev/null; then
    echo "🛡 Using iptables to block IP"
    iptables -A INPUT -s "$IP" -j DROP

    if [ -f /etc/sysconfig/iptables ]; then
        echo "💾 Saving iptables rules to /etc/sysconfig/iptables..."
        iptables-save > /etc/sysconfig/iptables
        echo "✅ IP $IP blocked and rules saved"
    else
        echo "⚠️ Warning: /etc/sysconfig/iptables not found. Install iptables-services to persist rules."
        echo "📌 You can install with: sudo yum install iptables-services"
    fi

    exit 0
else
    echo "❌ Neither iptables nor firewalld found. Cannot block IP."
    exit 1
fi

