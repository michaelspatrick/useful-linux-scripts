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
# Percona toolkit is highly recommended to be installed and available.
# The script will attempt to download only the necessary tools from the Percona
# website.  If that too fails, it will continue gracefully, but some key metrics
# will be missing.  This can also be skipped by the --skip-downloads flag.
#
# This script also gathers either /var/log/syslog or /var/log/messages.
# It will collect the last 1,000 lines from the log by default.
#
# Modify the Postgres connectivity section below and then you should be able
# to run the script.
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
BASEDIR=${TMPDIR}/metrics
DATETIME=`date +"%F_%H-%M-%S"`
HOSTNAME=`hostname`
DIRNAME="${HOSTNAME}_${DATETIME}"
CURRENTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
PTDEST=${BASEDIR}/${DIRNAME}

# Number of log entries to collect
NUM_LOG_LINES=1000

# Trap ctrl-c interrupts
trap die SIGINT

# Setup colors
if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
  NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
else
  NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
fi

# Display output messages with color
msg() {
  if [ "$COLOR" = true ]; then
    echo >&2 -e "${1-}"
  else
    echo >&2 "${1-}"
  fi
}

# Check that a command exists
exists() {
  command -v "$1" >/dev/null 2>&1 ;
}

# Get the script version number
version() {
  echo "Version ${VERSION}"
  exit
}

# Display a colored heading
heading() {
  msg "${PURPLE}${1}${NOFORMAT}"
}

# Cleanup temporary files and working directory
cleanup() {
  echo
  heading "Cleanup"
  echo -n "Deleting temporary files: "
  if [ -d "${PTDEST}" ]; then
    rm -rf ${PTDEST}
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped${NOFORMAT}"
  fi
}

die() {
  echo
  cleanup
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
-h, --help        Print this help and exit
-v, --verbose     Print script debug info
-V, --version     Print script version info
-f, --fast        When enabled, will not run OS commands which take over 60 seconds each
--no-color        Do not display colors
--skip-downloads  Do not attempt to download any Percona tools
EOF
  exit
}

parse_params() {
  # default values of variables set from params
  COLOR=true             # Whether or not to show colored output
  FAST=false             # Whether or not to run fast or slow (with more detail)
  CMD_TIME=60            # Longer running cmd execution time
  CMD_SHORT_TIME=3       # Shorter running cmd execution time
  SKIP_DOWNLOADS=false   # Whether to skip attempts to download Percona toolkit and scripts

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    -V | --version) version ;;
    --no-color) COLOR=false ;;
    --skip-downloads) SKIP_DOWNLOADS=true ;;
    -f | --fast) FAST=true; CMD_TIME=${CMD_SHORT_TIME} ;;
    -?*) die "Unknown option: $1" ;;
    *) break; die ;;
    esac
    shift
  done

  args=("$@")

  return 0
}

parse_params "$@"

if [ "$COLOR" = false ]; then
  NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
fi

# Check to ensure running as root
if [ "$EUID" -ne 0 ]; then
  HAVE_SUDO=false
else
  HAVE_SUDO=true
fi

heading "Notes"

echo -n "PostgreSQL Data Collection Version: "
msg "${GREEN}${VERSION}${NOFORMAT}"

echo -n "Metrics collection speed: "
if [ "$FAST" = true ]; then
  msg "${YELLOW}fast (${CMD_TIME} sec)${NOFORMAT}"
else
  msg "${GREEN}slow (${CMD_TIME} sec)${NOFORMAT}"
fi

# Get the Percona Toolkit Version
if exists pt-summary; then
  PT_EXISTS=true
  PT_SUMMARY=`which pt-summary`
  PT_VERSION_NUM=`${PT_SUMMARY} --version | egrep -o '[0-9]{1,}\.[0-9]{1,}'`
else
  if [ -f "${TMPDIR}/pt-summary" ]; then
    PT_EXISTS=true
    PT_SUMMARY=${TMPDIR}/pt-summary
    chmod +x ${PT_SUMMARY}
    PT_VERSION_NUM=`${PT_SUMMARY} --version | egrep -o '[0-9]{1,}\.[0-9]{1,}'`
  else
    echo -n "Warning: Percona Toolkit tool, pg-summary, not found.  Attempting download: "
    if [ "${SKIP_DOWNLOADS}" = false ]; then
      wget -cq -T 5 -P ${TMPDIR} percona.com/get/pt-summary
      if [ $? -eq 0 ]; then
        PT_EXISTS=true
        PT_SUMMARY="${TMPDIR}/pt-summary"
        chmod +x ${PT_SUMMARY}
        PT_VERSION_NUM=`${PT_SUMMARY} --version | egrep -o '[0-9]{1,}\.[0-9]{1,}'`
        msg "${GREEN}done${NOFORMAT}"
      else
        PT_EXISTS=false
        PT_VERSION_NUM=""
        msg "${RED}failed${NOFORMAT}"
      fi
    else
      msg "${YELLOW}skipped (per user request)${NOFORMAT}"
    fi
  fi
fi

if exists pt-pg-summary; then
  PT_PG_SUMMARY=`which pt-pg-summary`
else
  if [ -f "${TMPDIR}/pt-pg-summary" ]; then
    PT_EXISTS=true
    PT_PG_SUMMARY="${TMPDIR}/pt-pg-summary"
    chmod +x ${PT_PG_SUMMARY}
  else
    echo -n "Warning: Percona Toolkit tool, pg-pg-summary, not found.  Attempting download: "
    if [ "${SKIP_DOWNLOADS}" = false ]; then
      wget -cq -T 5 -P ${TMPDIR} percona.com/get/pt-pg-summary
      if [ $? -eq 0 ]; then
        PT_PG_SUMMARY=${TMPDIR}/pt-pg-summary
        chmod +x ${PT_PG_SUMMARY}
        msg "${GREEN}done${NOFORMAT}"
      else
        msg "${RED}failed${NOFORMAT}"
      fi
    else
      msg "${YELLOW}skipped (per user request)${NOFORMAT}"
    fi
  fi
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

# Get the newest Postgres PID
PG_PID=`pgrep -x postgres -n`

# Get the location of the PG config file
PG_CONFIG=`$PSQL_CONNECT_STR -t -c 'SHOW config_file' | xargs`
PG_HBA_CONFIG=`$PSQL_CONNECT_STR -t -c 'SHOW hba_file' | xargs`

echo -n "Percona Toolkit Version: "
if [ "$PT_EXISTS" = true ]; then
  msg "${GREEN}${PT_VERSION_NUM}${NOFORMAT}"
else
  msg "${YELLOW}not found${NOFORMAT}"
fi

echo -n "Attempt download of Percona toolkit (if needed): "
if [ "$SKIP_DOWNLOADS" = false ]; then
  msg "${GREEN}yes${NOFORMAT}"
else
  msg "${YELLOW}no${NOFORMAT}"
fi

echo -n "Postgres Version: "
msg "${GREEN}${PG_VERSION_STR}${NOFORMAT}"

echo -n "User permissions: "
if [ "$HAVE_SUDO" = true ] ; then
  msg "${GREEN}root${NOFORMAT}"
else
  msg "${YELLOW}unprivileged${NOFORMAT}"
fi

echo -n "Postgres Server PID (Latest): "
msg "${GREEN}${PG_PID}${NOFORMAT}"

echo -n "Postgres Server Configuration File: "
msg "${CYAN}${PG_CONFIG}${NOFORMAT}"

echo -n "Postgres Client Configuration File: "
msg "${CYAN}${PG_HBA_CONFIG}${NOFORMAT}"

echo -n "Base working directory: "
msg "${CYAN}${BASEDIR}${NOFORMAT}"

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
if ! exists $PT_SUMMARY; then
  msg "${ORANGE}warning - Percona Toolkit not found${NOFORMAT}"
else
  $PT_SUMMARY > ${PTDEST}/pt-summary.txt
  if [ $? -eq 0 ]; then
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${RED}failed${NOFORMAT}"
  fi
fi

echo -n "Collecting sysctl: "
sysctl -a > ${PTDEST}/sysctl_a.txt 2> /dev/null
msg "${GREEN}done${NOFORMAT}"

# Collect ps
echo -n "Collecting ps: "
ps auxf > ${PTDEST}/ps_auxf.txt
msg "${GREEN}done${NOFORMAT}"

# Collect top
echo -n "Collecting top: "
top -bn 1 > ${PTDEST}/top.txt
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
  echo -n "Collecting /var/log/messages (up to ${NUM_LOG_LINES} lines): "
  tail -n ${NUM_LOG_LINES} /var/log/messages > ${PTDEST}/messages
  msg "${GREEN}done${NOFORMAT}"
fi

# Copy syslog (if exists)
if [ -e /var/log/syslog ]; then
  echo -n "Collecting /var/log/syslog (up to ${NUM_LOG_LINES} lines): "
  tail -n ${NUM_LOG_LINES} /var/log/syslog > ${PTDEST}/syslog
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
echo -n "Collecting mpstat (${CMD_TIME} sec): "
if exists mpstat; then
  mpstat -A 1 ${CMD_TIME} > ${PTDEST}/mpstat.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
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
echo -n "Collecting vmstat (${CMD_TIME} sec): "
if exists vmstat; then
  vmstat 1 ${CMD_TIME} > ${PTDEST}/vmstat.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
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

echo -n "Collecting smartctl: "
if exists smartctl; then
  if [ "$HAVE_SUDO" = true ] ; then
    smartctl --scan | awk '{print $1}' | while read device; do { smartctl --xall "${device}"; } done > "${PTDEST}/smartctl.txt"
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped (insufficient user privileges)${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

echo -n "Collecting multipath: "
if exists multipath; then
  if [ "$HAVE_SUDO" = true ] ; then
    multipath -ll > "${PTDEST}/multipath_ll.txt"
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped (insufficient user privileges)${NOFORMAT}"
  fi
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
echo -n "Collecting iostat (${CMD_TIME} sec): "
if exists iostat; then
  iostat -dmx 1 ${CMD_TIME} > ${PTDEST}/iostat.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

echo -n "Collecting nfsiostat (${CMD_TIME} sec): "
if exists nfsiostat; then
  nfsiostat 1 ${CMD_TIME} > ${PTDEST}/nfsiostat.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

echo
heading "Networking"

echo -n "Collecting netstat: "
if exists netstat; then
  netstat -s > ${PTDEST}/netstat_s.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

echo -n "Collecting sar (${CMD_TIME} sec): "
if exists sar; then
  sar -n DEV 1 ${CMD_TIME} > ${PTDEST}/sar_dev.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi


echo
heading "PostgreSQL"
echo -n "Copying server configuration file: "
if [ -r "${PG_CONFIG}" ]; then
  cp ${PG_CONFIG} ${PTDEST}
  if [ $? -eq 0 ]; then
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${RED}failed${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped - insufficient read privileges${NOFORMAT}"
fi

echo -n "Copying client configuration file: "
if [ -r "${PG_HBA_CONFIG}" ]; then
  cp ${PG_HBA_CONFIG} ${PTDEST}
  if [ $? -eq 0 ]; then
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${RED}failed${NOFORMAT}"
  fi
else
  msg "${YELLOW}skipped - insufficient read privileges${NOFORMAT}"
fi

echo -n "Collecting PIDs: "
pgrep -x postgres > "${PTDEST}/postgres_PIDs.txt"
if [ $? -eq 0 ]; then
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${RED}failed${NOFORMAT}"
fi

echo -n "Copying limits: "
if [ -r "/proc/${PG_PID}/limits" ]; then
  cp "/proc/${PG_PID}/limits"  "${PTDEST}/proc_${PG_PID}_limits.txt"
  if [ $? -eq 0 ]; then
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${RED}failed${NOFORMAT}"
  fi
else
  msg "${RED}insufficient read privileges${NOFORMAT}"
fi

# Collect Postgres summary info using Percona Toolkit (if available)
echo "Collecting pt-pg-summary: "
if ! exists ${PT_PG_SUMMARY}; then
  msg "${RED}error - Percona Toolkit not found${NOFORMAT}"
else
  ${PT_PG_SUMMARY} -U ${PG_USER} --password=${PG_PASSWORD} > ${PTDEST}/pt-pg-summary.txt
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
if [ "${SKIP_DOWNLOADS}" = false ]; then
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
else
  msg "${YELLOW}skipped (per user request)${NOFORMAT}"
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
cleanup

exit 0
