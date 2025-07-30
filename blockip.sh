#!/bin/bash

# Check if run as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

# Check for argument
if [ -z "$1" ]; then
    echo "Usage: $0 <IP_ADDRESS>"
    exit 1
fi

IP="$1"

# Block the IP using iptables
echo "🚫 Blocking IP: $IP"
iptables -A INPUT -s "$IP" -j DROP

# Save iptables rules permanently
if command -v iptables-save &> /dev/null; then
    echo "💾 Saving iptables rules..."
    iptables-save > /etc/sysconfig/iptables
    echo "✅ IP $IP blocked and rules saved"
else
    echo "⚠️ iptables-save not found — rules may not persist after reboot"
fi
