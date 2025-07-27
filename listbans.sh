#!/bin/bash
# Script is a simple command to list bans from fail2ban using an iptables command

sudo iptables -n -L --line-numbers
