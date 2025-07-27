#!/bin/bash
#
# Simple firewall using ipset and iptables.  Implements a blacklist using well known blacklists from the web. 
# Also implements banning of entire countries.
# Some of the code is based upon: https://github.com/trick77/ipset-blacklist
#
# Cron entries:
# @reboot /bin/sleep 40 ; /bin/bash -c ". /home/centos/.bashrc ; /home/centos/firewall.sh --init"
# @daily /bin/bash -c ". /home/centos/.bashrc ; /home/centos/firewall.sh --report"
#
# ---------------------------------------------- Begin Configuration ----------------------------------------------

BLACKLIST_COUNTRIES=('ar' 'bd' 'bg' 'by' 'cn' 'co' 'iq' 'ir' 'kp' 'ly' 'mn' 'mu' 'pa' 'ro' 'ru' 'sd' 'tw' 'ua' 've' 'vn')
ETCDIR="/etc/firewall"
REPORT_EMAIL="toritejutsu@gmail.com"
VERBOSE=yes # probably set to "no" for cron jobs, default to yes

# List of URLs for IP blacklists. Currently, only IPv4 is supported in this script, everything else will be filtered.
BLACKLISTS=(
    # "file:///etc/ipset-blacklist/ip-blacklist-custom.list" # optional, for your personal nemeses (no typo, plural)
    "file:///etc/firewall/custom.list" # Custom list created by Mike Patrick
    "file:///etc/firewall/failed-logins.list" # Custom list created by Mike Patrick
    "https://www.projecthoneypot.org/list_of_ips.php?t=d&rss=1" # Project Honey Pot Directory of Dictionary Attacker IPs
    "https://check.torproject.org/cgi-bin/TorBulkExitList.py?ip=1.1.1.1"  # TOR Exit Nodes
    "http://danger.rulez.sk/projects/bruteforceblocker/blist.php" # BruteForceBlocker IP List
    "https://www.spamhaus.org/drop/drop.lasso" # Spamhaus Don't Route Or Peer List (DROP)
    "https://cinsscore.com/list/ci-badguys.txt" # C.I. Army Malicious IP List
    "https://lists.blocklist.de/lists/all.txt" # blocklist.de attackers
    "https://blocklist.greensnow.co/greensnow.txt" # GreenSnow
    "https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset" # Firehol Level 1
    "https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level2.netset" # Firehol Level 2
    "https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level3.netset" # Firehol Level 3
    "https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/stopforumspam_7d.ipset" # Stopforumspam via Firehol
    "https://www.binarydefense.com/banlist.txt" # Binary Defense Systems Artillery Threat Intelligence Feed and Banlist Feed
    # "https://raw.githubusercontent.com/ipverse/rir-ip/master/country/zz/ipv4-aggregated.txt" # Ban an entire country(-code), see https://github.com/ipverse/rir-ip
    # "https://raw.githubusercontent.com/ipverse/asn-ip/master/as/1234/ipv4-aggregated.txt" # Ban a specific autonomous system (ISP), see https://github.com/ipverse/asn-ip
)
MAXELEM=131072

# ----------------------------------------------- End Configuration -----------------------------------------------

# Check to ensure running as root
if [ "$EUID" -ne 0 ]; then
  if [[ ${VERBOSE:-no} == yes ]]; then
    echo "Must be run as root"
  fi
  exit 1
fi

function exists() { command -v "$1" >/dev/null 2>&1 ; }

# check for commands we need
if ! exists curl && exists egrep && exists grep && exists ipset && exists iptables && exists sed && exists sort && exists wc ; then
  echo >&2 "Error: searching PATH fails to find executables among: curl egrep grep ipset iptables sed sort wc"
  exit 1
fi

REPORT_SUBJECT="BLOCKED Packets report on $(hostname | tr 'a-z' 'A-Z')"
SAVEFILE="${ETCDIR}/iptables.save"
FORCE=yes # will create the ipset-iptable binding if it does not already exist
let IPTABLES_IPSET_RULE_NUMBER=1 # if FORCE is yes, the number at which place insert the ipset-match rule (default to 1)

# Help function
help() {
  echo "Usage: $0 <OPTION>"
  echo "Utilizes iptables and ipset to create a basic firewall with country banning, a blacklist, and whitelist."
  echo "Configuration files are stored in ${ETCDIR}."
  echo "One of the following parameters are required:"
  echo
  echo "  --destroy		Attempt to destroy and flush the firewall rules."
  echo "  --help		Show this message."
  echo "  --init		Ensure ipset is installed and setup the initial chains and match sets."
  echo "  --list		List chains and match sets."
  echo "  --reload-blacklist	Reload blacklist."
  echo "  --reload-countries	Reload countries blacklist."
  echo "  --reload-whitelist	Reload whitelist."
  echo "  --report		Email a report."
  echo "  --restore		Restore the rules from ${SAVEFILE}."
  echo "  --save		Save the rules to ${SAVEFILE}."
  echo "  --stats		Show sats on number of entries per match set."
  echo "  --status		Show the status of the rules."
  echo
  echo "Exit status:"
  echo "0  if OK"
  echo "1  if not run as root"
}

whitelist() {
  iptables -X whitelist
  # Whitelist specified IPs
  if [[ ${VERBOSE:-no} == yes ]]; then
    echo "Creating whitelist..."
  fi
  ipset create whitelist hash:ip hashsize 4096
  for IP in $(cat ${ETCDIR}/whitelist.list)
  do
    if [[ ${VERBOSE:-no} == yes ]]; then
      echo "Whitelisting $IP"
    fi
    ipset add whitelist $IP
  done
  #iptables -I whitelist -m set --match-set "whitelist" src -j ACCEPT -m comment --comment "whitelist"
}

ban_countries() {
  iptables -X countries
  for COUNTRY in "${BLACKLIST_COUNTRIES[@]}"; do
    ipset destroy ${COUNTRY}
  done

  # Block specified countries
  if [[ ${VERBOSE:-no} == yes ]]; then
    echo "Blocking specific country..."
  fi
  for COUNTRY in "${BLACKLIST_COUNTRIES[@]}"; do
    ipset create "${COUNTRY}" hash:net
  done
  iptables -v -F countries
  for i in "${BLACKLIST_COUNTRIES[@]}"; do
    if [[ ${VERBOSE:-no} == yes ]]; then
      echo "Ban IP of country ${i}"
    fi
    ipset flush "${i}"
    for IP in $(wget --no-check-certificate -O - https://www.ipdeny.com/ipblocks/data/countries/${i}.zone)
    do
      ipset add "${i}" $IP
    done
    iptables -I countries -m set --match-set "${i}" src -j DROP -m comment --comment "Block .${i}"
  done
}

# Function to create rules
create() {
  whitelist
  blacklist
  ban_countries
  save_config
}

# Function to initialize the iptables rules
init() {
  mkdir -p ${ETCDIR}
  yum -y install ipset

  iptables -N countries
  iptables -I INPUT -j countries -m comment --comment "Blocked countries"
  iptables -I FORWARD -j countries -m comment --comment "Blocked countries"

  iptables -N blacklist
  iptables -I INPUT -m set --match-set blacklist src -j DROP
  iptables -I FORWARD -m set --match-set blacklist src -j DROP

  iptables -N whitelist
  iptables -I INPUT -m set --match-set whitelist src -j ACCEPT
  iptables -I FORWARD -m set --match-set whitelist src -j ACCEPT
}

# Function to destroy the iptables rules
destroy() {
  iptables -F
  iptables -X blacklist
  iptables -X whitelist
  iptables -X countries
  for COUNTRY in "${BLACKLIST_COUNTRIES[@]}"; do
    ipset destroy ${COUNTRY}
  done
}

# Function to show status
status() {
  iptables -v -n -L
}

# Function to save configuration to ${SAVEFILE}
save_config() {
  ipset save > ${SAVEFILE}
}

# Function to read configuration from ${SAVEFILE}
read_config() {
  ipset restore < ${SAVEFILE}
}

# Function to list rules
list() {
  ipset list
}

# Function to email a report of activity
report() {
  HOST=$(cat /etc/hostname | tr 'a-z' 'A-Z')
  reportsender="cron@$HOST"
  tempdir="/tmp"
  file1="iptables_report1.txt"
  file2="iptables_report2.txt"

  #------------ Build the header of the mail to send ------------
  echo "From: $reportsender" > $tempdir/$file1
  echo "To: $REPORT_EMAIL" >> $tempdir/$file1
  echo "Subject: $REPORT_SUBJECT" >> $tempdir/$file1
  echo "MIME-Version: 1.0" >> $tempdir/$file1
  echo 'Content-Type: text/html; charset="ISO-8859-15"' >> $tempdir/$file1
  echo "" >> $tempdir/$file1
  echo "<br />" >> $tempdir/$file1
  echo -e "<font size=3 FACE='Courier'><pre>" >> $tempdir/$file1

  # Formatted message starts here
  # Add the country at the end of each line
  # Load the header and data to the temporary file 2
  echo -e "Packets Bytes Source \n======= ========= ======" >$tempdir/$file2
  /sbin/iptables -L -n -v | /bin/grep -v '^ 0' | /bin/grep 'match-set' | /usr/bin/awk '{print $1" "$2" "$11}' >> $tempdir/$file2

  # Format temp file2 into temp file1
  cat $tempdir/$file2 | column -t >> $tempdir/$file1

  # Add the last HTML preformatting End
  echo -e "</pre>" >> $tempdir/$file1
  echo "" >> $tempdir/$file1

  #----------------- Send the prepared email ---------------------------
  # now format the report and send it by email
  cat $tempdir/$file1 | /usr/sbin/sendmail -t
  rm $tempdir/$file1 $tempdir/$file2

  # Reset the iptables counters
  /sbin/iptables -Z
}

blacklist() {
  # iptables -X blacklist

  DO_OPTIMIZE_CIDR=no
  if exists iprange && [[ ${OPTIMIZE_CIDR:-yes} != no ]]; then
    DO_OPTIMIZE_CIDR=yes
  fi

  if [[ ! -d $(dirname "${ETCDIR}/iptables.list") || ! -d $(dirname "${ETCDIR}/iptables.restore") ]]; then
    echo >&2 "Error: missing directory(s): $(dirname "${ETCDIR}/iptables.list" "${ETCDIR}/iptables.restore"|sort -u)"
    exit 1
  fi

  # create the ipset if needed (or abort if does not exists and FORCE=no)
  if ! ipset list -n|command grep -q "blacklist"; then
    if [[ ${FORCE:-no} != yes ]]; then
      echo >&2 "Error: ipset does not exist yet, add it using:"
      echo >&2 "# ipset -exist -quiet create blacklist hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}"
      exit 1
    fi
    if ! ipset create -exist -quiet "blacklist" hash:net family inet hashsize "${HASHSIZE:-16384}" maxelem "${MAXELEM:-65536}"; then
      echo >&2 "Error: while creating the initial ipset"
      exit 1
    fi
  fi

  # create the iptables binding if needed (or abort if does not exists and FORCE=no)
  if ! iptables -nvL INPUT|command grep -q "match-set blacklist"; then
    # we may also have assumed that INPUT rule n°1 is about packets statistics (traffic monitoring)
    if [[ ${FORCE:-no} != yes ]]; then
      echo >&2 "Error: iptables does not have the needed ipset INPUT rule, add it using:"
      echo >&2 "# iptables -I INPUT ${IPTABLES_IPSET_RULE_NUMBER:-1} -m set --match-set blacklist src -j DROP"
      exit 1
    fi
    if ! iptables -I INPUT "${IPTABLES_IPSET_RULE_NUMBER:-1}" -m set --match-set "blacklist" src -j DROP; then
      echo >&2 "Error: while adding the --match-set ipset rule to iptables"
      exit 1
    fi
  fi

  # Look for failed SSH logins and break-in attempts in the logs
  TMPFILE="/tmp/IP.txt"
  cat ${ETCDIR}/failed-logins.list > $TMPFILE
  cat /var/log/secure | grep BREAK-IN | grep -Po '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' >> $TMPFILE
  cat /var/log/fail2ban.log | grep sshd | grep -Po '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' >> $TMPFILE
  cat $TMPFILE | sort | uniq > ${ETCDIR}/failed-logins.list

  IP_BLACKLIST_TMP=$(mktemp)
  for i in "${BLACKLISTS[@]}"
  do
    IP_TMP=$(mktemp)
    (( HTTP_RC=$(curl -L -A "blacklist-update/script/github" --connect-timeout 10 --max-time 10 -o "$IP_TMP" -s -w "%{http_code}" "$i") ))
    if (( HTTP_RC == 200 || HTTP_RC == 302 || HTTP_RC == 0 )); then # "0" because file:/// returns 000
      command grep -Po '^(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?' "$IP_TMP" | sed -r 's/^0*([0-9]+)\.0*([0-9]+)\.0*([0-9]+)\.0*([0-9]+)$/\1.\2.\3.\4/' >> "$IP_BLACKLIST_TMP"
      [[ ${VERBOSE:-yes} == yes ]] && echo -n "."
    elif (( HTTP_RC == 503 )); then
      echo -e "\\nUnavailable (${HTTP_RC}): $i"
    else
      echo >&2 -e "\\nWarning: curl returned HTTP response code $HTTP_RC for URL $i"
    fi
    rm -f "$IP_TMP"
  done

  # sort -nu does not work as expected
  sed -r -e '/^(0\.0\.0\.0|10\.|127\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.|192\.168\.|22[4-9]\.|23[0-9]\.)/d' "$IP_BLACKLIST_TMP"|sort -n|sort -mu >| "${ETCDIR}/iptables.list"
  if [[ ${DO_OPTIMIZE_CIDR} == yes ]]; then
    if [[ ${VERBOSE:-no} == yes ]]; then
      echo -e "\\nAddresses before CIDR optimization: $(wc -l "${ETCDIR}/iptables.list" | cut -d' ' -f1)"
    fi
    < "${ETCDIR}/iptables.list" iprange --optimize - > "$IP_BLACKLIST_TMP" 2>/dev/null
    if [[ ${VERBOSE:-no} == yes ]]; then
      echo "Addresses after CIDR optimization:  $(wc -l "$IP_BLACKLIST_TMP" | cut -d' ' -f1)"
    fi
    cp "$IP_BLACKLIST_TMP" "${ETCDIR}/iptables.list"
  fi

  rm -f "$IP_BLACKLIST_TMP"

  # family = inet for IPv4 only
cat >| "${ETCDIR}/iptables.restore" <<EOF
create blacklist-tmp -exist -quiet hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
create blacklist -exist -quiet hash:net family inet hashsize ${HASHSIZE:-16384} maxelem ${MAXELEM:-65536}
EOF

  # can be IPv4 including netmask notation
  # IPv6 ? -e "s/^([0-9a-f:./]+).*/add blacklist-tmp \1/p" \ IPv6
  sed -rn -e '/^#|^$/d' \
    -e "s/^([0-9./]+).*/add blacklist-tmp \\1/p" "${ETCDIR}/iptables.list" >> "${ETCDIR}/iptables.restore"

cat >> "${ETCDIR}/iptables.restore" <<EOF
swap blacklist blacklist-tmp
destroy blacklist-tmp
EOF

  ipset -file  "${ETCDIR}/iptables.restore" restore

  if [[ ${VERBOSE:-no} == yes ]]; then
    echo
    echo "Blacklisted addresses found: $(wc -l "${ETCDIR}/iptables.list" | cut -d' ' -f1)"
  fi
}

read_dom () {
  local IFS=\>
  read -d \< ENTITY CONTENT
  local ret=$?
  TAG_NAME=${ENTITY%% *}
  ATTRIBUTES=${ENTITY#* }
  return $ret
}

parse_dom () {
  if [[ $TAG_NAME = "ipset" ]] ; then
    eval local $ATTRIBUTES
    NAME=$name
  elif [[ $TAG_NAME = "numentries" ]] ; then
    eval local $ATTRIBUTES
    NUMENTRIES=$CONTENT
    #echo "$NAME: $NUMENTRIES"
    printf "%-14s %7s\n" $NAME $NUMENTRIES
  fi
}

stats() {
  echo "Match Set      Entries"
  echo "---------      -------"
  ipset -output xml list | while read_dom; do parse_dom; done
}

# Check parameters
if [ "$1" = "--status" ]; then
  status
  exit 0
elif [ "$1" = "--destroy" ]; then
  destroy
  exit 0
elif [ "$1" = "--init" ]; then
  init
  create
  save_config
  exit 0
elif [ "$1" = "--list" ]; then
  list
  exit 0
elif [ "$1" = "--reload-blacklist" ]; then
  blacklist
  save_config
  exit 0
elif [ "$1" = "--reload-countries" ]; then
  ban_countries
  save_config
  exit 0
elif [ "$1" = "--reload-whitelist" ]; then
  whitelist
  save_config
  exit 0
elif [ "$1" = "--report" ]; then
  report
  exit 0
elif [ "$1" = "--restore" ]; then
  read_config
  exit 0
elif [ "$1" = "--save" ]; then
  save_config
  exit 0
elif [ "$1" = "--stats" ]; then
  stats
  exit 0
elif [ "$1" = "--help" ]; then
  help
  exit 0
else
  help
  exit 0
fi
