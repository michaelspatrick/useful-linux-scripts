#!/usr/bin/env bash
#
#  Script collects numerous metrics for PostgreSQL and the Operating System.
#  It then compresses all the data into a single archive file which can then
#  be shared with Support.  Script is based upon Percona KB0010933 with a
#  number of enhancements.
#
#  Written by Michael Patrick (michael.patrick@percona.com)
#  Version 0.1 - May 18, 2023
#
#  It is recommended to run the script as a privileged user (superuser,
#  rds_superuser etc) or some account with pg_monitor privilege.  You can
#  safely ignore any warnings.
#
#  Percona toolkit is highly recommended to be installed and available.  If
#  not the script, will still continue gracefully, but some key metrics will
#  be missing.
#
#  Modify the Postgres connectivity section below and then you should be able
#  to run the script.  You should execute it with sudo as follows:
#  sudo ./pg-collect.sh
#
#  Use at your own risk!
#

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
DATETIME=`date +"%FT%H%M%S"`
HOSTNAME=`hostname`
DIRNAME="${HOSTNAME}-${DATETIME}"
CURRENTDIR=`pwd`
PTDEST=${BASEDIR}/${DIRNAME}

# Trap ctrl-c interrupts
trap cleanup SIGINT

# Display output messages with color
msg() {
  echo >&2 -e "${1-}"
}

# Cleanup temporary files and working directory
cleanup() {
  trap - SIGINT
  echo -n "Performing cleanup: "
  if [ -f "${TMPDIR}/gather.sql" ]; then
    rm -f ${TMPDIR}/gather.sql
  fi
  if [ -d "${PTDEST}" ]; then
    sudo rm -rf ${PTDEST}
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${YELLOW}skipped${NOFORMAT}"
  fi
}

# Check that a command exists
exists() {
  command -v "$1" >/dev/null 2>&1 ;
}

# Setup colors
if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
  NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
else
  NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
fi

# Check to ensure running as root
if [ "$EUID" -ne 0 ]; then
  msg "${RED}Error: Must be run as root${NOFORMAT}"
  exit 1
fi

# Create the working directory
mkdir -p ${PTDEST}

# Collect summary info using Percona Toolkit (if available)
echo -n "Collecting pt-summary: "
if ! exists pt-summary; then
  msg "${RED}error - Percona Toolkit not found${NOFORMAT}"
  #exit 1
else
  sudo pt-summary > ${PTDEST}/pt-summary.txt
  if [ $? -eq 0 ]; then
    msg "${GREEN}done${NOFORMAT}"
  else
    msg "${RED}failed${NOFORMAT}"
  fi
fi

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

# Copy messages (if exists)
if [ -e /var/log/messages ]; then
  echo -n "Copying /var/log/messages: "
  cp /var/log/messages ${PTDEST}/
  #tail -n 1000 /var/log/messages > ${PTDEST}/messages
  msg "${GREEN}done${NOFORMAT}"
fi

# Copy syslog (if exists)
if [ -e /var/log/syslog ]; then
  echo -n "Copying /var/log/syslog: "
  cp /var/log/syslog ${PTDEST}/
  #tail -n 1000 /var/log/syslog > ${PTDEST}/syslog
  msg "${GREEN}done${NOFORMAT}"
fi

# Copy the journalctl output
echo -n "Collecting journalctl: "
journalctl -e > ${PTDEST}/journalctl.txt
msg "${GREEN}done${NOFORMAT}"

# Get the Postgres gather SQL script and run it
echo -n "Downloading gather.sql: "
# For version 9.6.x
#curl -sLO https://raw.githubusercontent.com/percona/support-snippets/master/postgresql/pg_gather/gather_old.sql
# For version 10.0 and up
curl -sLO https://raw.githubusercontent.com/percona/support-snippets/master/postgresql/pg_gather/gather.sql
sudo mv gather.sql ${TMPDIR}
msg "${GREEN}done${NOFORMAT}"
echo -n "Executing gather.sql: "
${PSQL_CONNECT_STR} -X -f ${TMPDIR}/gather.sql > ${PTDEST}/psql_gather.txt
if [ $? -eq 0 ]; then
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${RED}failed${NOFORMAT}"
fi

# Collect hardware information
echo -n "Collecting dmesg: "
sudo dmesg >  ${PTDEST}/dmesg.txt
sudo dmesg -T >  ${PTDEST}/dmesg_t.txt
msg "${GREEN}done${NOFORMAT}"
echo -n "Collecting ulimit: "
ulimit -a > ${PTDEST}/ulimit_a.txt
msg "${GREEN}done${NOFORMAT}"
echo -n "Collecting numactl: "
if exists numactl; then
  sudo numactl --hardware  >  ${PTDEST}/numactl-hardware.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# IO related
echo -n "Collecting lsblk: "
if exists lsblk; then
  sudo lsblk --all > ${PTDEST}/lsblk-all.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# lv/pv/vg only for systems with LVM
echo -n "Collecting lvdisplay: "
if exists lvdisplay; then
  sudo lvdisplay --all --maps > ${PTDEST}/lvdisplay-all-maps.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi
echo -n "Collecting pvdisplay: "
if exists pvdisplay; then
  sudo pvdisplay --maps > ${PTDEST}/pvdisplay-maps.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi
echo -n "Collecting pvs: "
if exists pvs; then
  sudo pvs -v > ${PTDEST}/pvs_v.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi
echo -n "Collecting vgdisplay: "
if exists vgdisplay; then
  sudo vgdisplay > ${PTDEST}/vgdisplay.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# nfsstat for systems with NFS mounts
echo -n "Collecting nfsstat: "
if exists nfsstat; then
  sudo nfsstat -m > ${PTDEST}/nfsstat_m.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi
echo -n "Collecting nfsiostat: "
if exists fsiostat; then
  sudo nfsiostat 1 120 > ${PTDEST}/nfsiostat.txt
  msg "${GREEN}done${NOFORMAT}"
else
  msg "${YELLOW}skipped${NOFORMAT}"
fi

# Compress files for sending to Percona
cd ${BASEDIR}
sudo chmod a+r ${DIRNAME} -R
echo "Compressing files:"
DEST_TGZ="$(dirname ${PTDEST})/${DIRNAME}.tar.gz"
sudo tar czvf "${DEST_TGZ}" ${DIRNAME}

# Do Cleanup
cleanup

echo -n "File saved to: "
msg "${CYAN}${DEST_TGZ}${NOFORMAT}"

exit 0
