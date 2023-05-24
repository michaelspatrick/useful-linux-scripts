#!/bin/bash
#
# Script collects numerous metrics for PostgreSQL and the Operating System.
# It then compresses all the data into a single archive file which can then
# be shared with Support.  Script is based upon Percona KB0010933 with a
# number of enhancements.
#
# Written by Michael Patrick (michael.patrick@percona.com)
# Version 0.1 - May 18, 2023
#
# It is recommended to run the script as a privileged user (superuser,
# rds_superuser etc), but it will run as any user.  You can safely ignore any
# warnings.
#
# Percona toolkit is highly recommended to be installed and available.  If
# not the script, will still continue gracefully, but some key metrics will
# be missing.
#
# This script also gathers either /var/log/syslog or /var/log/messages.
# There are commented lines if you would prefer to only grab something like
# the last 1,000 lines from the log instead.
#
# Modify the Postgres connectivity section below and then you should be able
# to run the script.
#
# If you run it with sudo or as root, you will get more metrics but it should
# execute just fine without sudo.
#
# Use at your own risk!
#

VERSION=0.1

# Postgres connectivity
PG_USER="postgres"
PG_PASSWORD="password"
PG_DBNAME="postgres"
PSQL_CONNECT_STR="psql -U${PG_USER} -d ${PG_DBNAME}"

# Set postgres password in the environment
export PGPASSWORD="${PG_PASSWORD}"

# Setup directory paths
TMPDIR=/tmp
BASEDIR=${TMPDIR}/pt
DATETIME=`date +"%F_%H-%M-%S"`
HOSTNAME=`hostname`
DIRNAME="${HOSTNAME}_${DATETIME}"
CURRENTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
PTDEST=${BASEDIR}/${DIRNAME}

# Trap ctrl-c interrupts
trap cleanup SIGINT

# Display output messages with color
msg() {
  if [ "$COLOR" = true ]; then
    echo >&2 -e "${1-}"
  else
    echo >&2 "${1-}"
  fi
}

# Cleanup temporary files and working directory
cleanup() {
  trap - SIGINT
  echo -n "Deleting temporary files: "
  if [ -d "${PTDEST}" ]; then
    rm -rf ${PTDEST}
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped${NOFORMAT}"
  fi
}

# Check that a command exists
exists() {
  command -v "$1" >/dev/null 2>&1 ;
}

version() {
  echo "Version ${VERSION}"
  exit
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

usage() {
  cat << EOF # remove the space between << and EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-V] [-f]

Script collects various Operating System and PostgreSQL diagnostic information and stores output in an archive file.

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-V, --version   Print script version info
-f, --fast      When enabled, will not run OS commands which take over 60 seconds each
--no-color      Do not display colors
EOF
  exit
}

parse_params() {
  # default values of variables set from params
  flag=0
  param=''
  COLOR=true
  FAST=false

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    -V | --version) version ;;
    --no-color) COLOR=false ;;
    -f | --fast) FAST=true ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  return 0
}

parse_params "$@"

# Setup colors
if [ "$COLOR" = true ]; then
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
else
  NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
fi

heading() {
  msg "${PURPLE}${1}${NOFORMAT}"
}

# Check to ensure running as root
if [ "$EUID" -ne 0 ]; then
  HAVE_SUDO=false
else
  HAVE_SUDO=true
fi

# Get the Percona Toolkit Version
if exists pt-summary; then
  PT_EXISTS=true
  PT_VERSION_NUM=`pt-summary --version | egrep -o '[0-9]{1,}\.[0-9]{1,}'`
else
  PT_EXISTS=false
  PT_VERSION_NUM=""
fi

# Get the Postgres Version
if exists pg_config; then
  PG_VERSION_STR=`pg_config --version`
fi
if exists psql; then
  PSQL_EXISTS=true
  PG_VERSION_NUM=`psql -V | egrep -o '[0-9]{1,}\.[0-9]{1,}'`
else
  PSQL_EXISTS=false
fi

heading "Notes"
echo -n "PostgreSQL Data Collection Version: "
msg "${GREEN}${VERSION}${NOFORMAT}"

echo -n "Metrics collection speed: "
if [ "$FAST" = true ]; then
  msg "${YELLOW}fast${NOFORMAT}"
else
  msg "${GREEN}slow${NOFORMAT}"
fi

echo -n "Percona Toolkit Version: "
if [ "$PT_EXISTS" = true ]; then
  msg "${GREEN}${PT_VERSION_NUM}${NOFORMAT}"
else
  msg "${YELLOW}not found${NOFORMAT}"
fi

echo -n "Postgres Version: "
msg "${GREEN}${PG_VERSION_STR}${NOFORMAT}"

echo -n "User permissions: "
if [ "$HAVE_SUDO" = true ] ; then
  msg "${GREEN}root${NOFORMAT}"
else
  msg "${YELLOW}unprivileged${NOFORMAT}"
fi

# Create the working directory
echo -n "Temporary working directory: "
msg "${CYAN}${PTDEST}${NOFORMAT}"
echo -n "Creating temporary directory: "
mkdir -p ${PTDEST}
if [ $? -eq 0 ]; then
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${RED}failed${NOFORMAT}"
  exit 1
fi

echo
heading "Operating System"

# Collect summary info using Percona Toolkit (if available)
echo -n "Collecting pt-summary: "
if ! exists pt-summary; then
  msg "${ORANGE}warning - Percona Toolkit not found${NOFORMAT}"
else
  pt-summary > ${PTDEST}/pt-summary.txt
  if [ $? -eq 0 ]; then
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${RED}failed${NOFORMAT}"
  fi
fi

# Collect process information
echo -n "Collecting ps: "
ps auxf > ${PTDEST}/ps_auxf.txt
msg "${GREEN}done${NOFORMAT}"

# Collect process information
echo -n "Collecting top: "
top -n 1 > ${PTDEST}/top.txt
msg "${GREEN}done${NOFORMAT}"

# Collect OS information
echo -n "Collecting uname: "
uname -a > ${PTDEST}/uname_a.txt
msg "${GREEN}done${NOFORMAT}"

# Collect kernel information
echo -n "Collecting dmesg: "
if [ "$HAVE_SUDO" = true ] ; then
  sudo dmesg > ${PTDEST}/dmesg.txt
  sudo dmesg -T > ${PTDEST}/dmesg_t.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped (insufficient user privileges)${NOFORMAT}"
fi

echo
heading "Logging"

# Copy messages (if exists)
if [ -e /var/log/messages ]; then
  echo -n "Collecting /var/log/messages: "
  #cp /var/log/messages ${PTDEST}/
  tail -n 1000 /var/log/messages > ${PTDEST}/messages
  msg "${GREEN}done${NOFORMAT}"
fi

# Copy syslog (if exists)
if [ -e /var/log/syslog ]; then
  echo -n "Collecting /var/log/syslog: "
  #cp /var/log/syslog ${PTDEST}/
  tail -n 1000 /var/log/syslog > ${PTDEST}/syslog
  msg "${GREEN}done${NOFORMAT}"
fi

# Copy the journalctl output
echo -n "Collecting journalctl: "
journalctl -e > ${PTDEST}/journalctl.txt
msg "${GREEN}done${NOFORMAT}"

echo
heading "Resource Limits"

# Ulimit
echo -n "Collecting ulimit: "
ulimit -a > ${PTDEST}/ulimit_a.txt
msg "${GREEN}done${NOFORMAT}"

echo
heading "Swapping"

# Swappiness
echo -n "Collecting swappiness: "
cat /proc/sys/vm/swappiness > ${PTDEST}/swappiness.txt
msg "${GREEN}done${NOFORMAT}"

echo
heading "NUMA"

# Numactl
echo -n "Collecting numactl: "
if exists numactl; then
  numactl --hardware > ${PTDEST}/numactl-hardware.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

echo
heading "CPU"

# cpuinfo
echo -n "Collecting cpuinfo: "
cat /proc/cpuinfo > ${PTDEST}/cpuinfo.txt
msg "${GREEN}done${NOFORMAT}"

# mpstat
echo -n "Collecting mpstat (60 sec): "
if [ "$FAST" = false ]; then
  if exists mpstat; then
    mpstat -A 1 60 > ${PTDEST}/mpstat.txt
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped (fast option chosen)${NOFORMAT}"
fi

echo
heading "Memory"

# meminfo
echo -n "Collecting meminfo: "
cat /proc/meminfo > ${PTDEST}/meminfo.txt
msg "${GREEN}done${NOFORMAT}"

# Memory
echo -n "Collecting free/used memory: "
free -m > ${PTDEST}/free_m.txt
msg "${GREEN}done${NOFORMAT}"

# vmstat
echo -n "Collecting vmstat (60 sec): "
if [ "$FAST" = false ]; then
  if exists vmstat; then
    vmstat 1 60 > ${PTDEST}/vmstat.txt
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped (fast option chosen)${NOFORMAT}"
fi

echo
heading "Storage"

# Disk info
echo -n "Collecting df: "
if exists df; then
  df -k > ${PTDEST}/df_k.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# Block devices
echo -n "Collecting lsblk: "
if exists lsblk; then
  lsblk -o KNAME,SCHED,SIZE,TYPE,ROTA > ${PTDEST}/lsblk.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# lsblk
echo -n "Collecting lsblk (all): "
if exists lsblk; then
  lsblk --all > ${PTDEST}/lsblk-all.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# lvdisplay (only for systems with LVM)
echo -n "Collecting lvdisplay: "
if exists lvdisplay; then
  if [ "$HAVE_SUDO" = true ] ; then
    sudo lvdisplay --all --maps > ${PTDEST}/lvdisplay-all-maps.txt
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped (insufficient user privileges)${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# pvdisplay (only for systems with LVM)
echo -n "Collecting pvdisplay: "
if exists pvdisplay; then
  if [ "$HAVE_SUDO" = true ] ; then
    sudo pvdisplay --maps > ${PTDEST}/pvdisplay-maps.txt
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped (insufficient user privileges)${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# pvs (only for systems with LVM)
echo -n "Collecting pvs: "
if exists pvs; then
  if [ "$HAVE_SUDO" = true ] ; then
    sudo pvs -v > ${PTDEST}/pvs_v.txt
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped (insufficient user privileges)${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# vgdisplay (only for systems with LVM)
echo -n "Collecting vgdisplay: "
if exists vgdisplay; then
  if [ "$HAVE_SUDO" = true ] ; then
    sudo vgdisplay > ${PTDEST}/vgdisplay.txt
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped (insufficient user privileges)${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# nfsstat for systems with NFS mounts
echo -n "Collecting nfsstat: "
if exists nfsstat; then
  nfsstat -m > ${PTDEST}/nfsstat_m.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

echo
heading "I/O"

# iostat
echo -n "Collecting iostat (60 sec): "
if [ "$FAST" = false ]; then
  if exists iostat; then
    iostat -dmx 1 60 > ${PTDEST}/iostat.txt
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped (fast option chosen)${NOFORMAT}"
fi

echo -n "Collecting nfsiostat: "
if exists nfsiostat; then
  nfsiostat 1 120 > ${PTDEST}/nfsiostat.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

echo
heading "PostgreSQL"

# Collect Postgres summary info using Percona Toolkit (if available)
echo "Collecting pt-pg-summary: "
if ! exists pt-pg-summary; then
  msg "${RED}error - Percona Toolkit not found${NOFORMAT}"
  #exit 1
else
  pt-pg-summary -U ${PG_USER} --password=${PG_PASSWORD} > ${PTDEST}/pt-pg-summary.txt
  if [ $? -eq 0 ]; then
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${RED}failed${NOFORMAT}"
  fi
fi

# Get the Postgres gather SQL script and run it
if awk "BEGIN {exit !($PG_VERSION_NUM >= 10.0)}"; then
  # For versions greater than 10.0, download this SQL script
  SQLFILE="gather.sql"
else
  # For earlier versions, download this SQL script
  SQLFILE="gather_old.sql"
fi
echo -n "Downloading '${SQLFILE}': "
if [ "$PSQL_EXISTS" = true ]; then
  curl -sL https://raw.githubusercontent.com/percona/support-snippets/master/postgresql/pg_gather/${SQLFILE} --output ${PTDEST}/${SQLFILE}
  if [ $? -eq 0 ]; then
    msg "${GREEN}done${NOFORMAT}"

    echo -n "Executing '${SQLFILE}' (20+ sec): "
    if [ -f "$PTDEST/$SQLFILE" ]; then
      ${PSQL_CONNECT_STR} -X -f ${PTDEST}/${SQLFILE} > ${PTDEST}/psql_gather.txt
      if [ $? -eq 0 ]; then
        msg "${GREEN}done${NOFORMAT}"
      else
        msg "${RED}failed${NOFORMAT}"
      fi
    else
      msg "${RED}failed${NOFORMAT}"
    fi
  else
    msg "${RED}failed (file does not exist)${NOFORMAT}"
  fi
else
  msg "${RED}failed (psql does not exist)${NOFORMAT}"
fi

echo
heading "Preparing Data Archive"

# Compress files for sending to Percona
cd ${BASEDIR}
chmod a+r ${DIRNAME} -R
echo "Compressing files:"
DEST_TGZ="$(dirname ${PTDEST})/${DIRNAME}.tar.gz"
tar czvf "${DEST_TGZ}" ${DIRNAME}

echo -n "File saved to: "
msg "${CYAN}${DEST_TGZ}${NOFORMAT}"

# Do Cleanup
echo
heading "Cleanup"
cleanup

exit 0
