#!/usr/bin/env bash
#
# This script uses pt-secure-collect from the Percona Toolkit to sanitize SQL statements in a text file.
# The original tool requires there be a ";" at the end of each line.
# Created by Michael Patrick with special thanks to Michael Benshoof for providing the regex which is used
# with a sed command to append a semicolon to each SQL statement.
# This effectively solves the problem for output from SHOW ENGINE INNODB STATUS, SHOW PROCESSLIST, and other
# SQL commands in MySQL where a semicolon is stripped off the end.
#

version=0.1

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat << EOF # remove the space between << and EOF, this is due to web plugin issue
Usage: $(basename "${BASH_SOURCE[0]}") [-d] [-h] [-v] -i <input-file> -o <output-file>

Script utilizes pt-secure-collect from the Percona Toolkit to strip PII data
from within SQL commands in a text file and writes to an output file. This
utility works around an issue where all SQL queries must have a trailing
semicolon for pt-secure-collect to work properly.

Available options:

-d, --debug        Print script debug info
-h, --help         Print this help and exit
-i, --input-file   Read the input text file
-o, --output-file  Write the output to a text file
-v, --version      Show version information
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  setup_colors
  echo >&2 -e "${1-}"
}

version() {
  msg "${0}"
  msg "Version ${version}"
  msg "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>."
  msg "This is free software: you are free to change and redistribute it."
  msg "There is NO WARRANTY, to the extent permitted by law."
  msg "Written by Michael Patrick."
  exit 0
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  setup_colors
  if [ "$show_debug" = true ]; then
    debug
  fi
  exit "$code"
}

debug() {
  msg "${RED}Read parameters:${NOFORMAT}"
  msg "- input-file: ${input_file}"
  msg "- output-file: ${output_file}"
  msg "- arguments: ${args[*]-}"
}

parse_params() {
  setup_colors
  # default values of variables set from params
  input_file=''
  output_file=''
  show_debug=false

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -d | --debug) show_debug=true; set -x ;;
    --no-color) NO_COLOR=1 ;;
    -i | --input-file)
      input_file="${2-}"
      shift
      ;;
    -o | --output-file)
      output_file="${2-}"
      shift
      ;;
    -v | --version) version ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [[ -z "${input_file-}" ]] && die "${RED}Missing required parameter: input-file${NOFORMAT}"
  [[ -z "${output_file-}" ]] && die "${RED}Missing required parameter: output-file${NOFORMAT}"

  return 0
}

parse_params "$@"
setup_colors

# check whether input file exists
if [ ! -f ${input_file} ]; then
  die "${RED}Input file, ${input_file}, does not exist!${NOFORMAT}"
fi

# check whether pt-secure-collect command exists
if ! command -v pt-secure-collect &> /dev/null; then
  die "${RED}The utility, pt-secure-collect, was not found.  Please install the latest version of the Percona Toolkit.${NOFORMAT}"
fi

# perform replace operation
if [ -z ${output_file+x} ]; then
  sed -r '/^(INSERT|UPDATE|SELECT|DELETE)/ s/$/;/' ${input_file} | sed -r 's/;;/;/' | pt-secure-collect sanitize --no-sanitize-hostnames
else
  sh -c "sed -r '/^(INSERT|UPDATE|SELECT|DELETE)/ s/$/;/' ${input_file} | sed -r 's/;;/;/' | pt-secure-collect sanitize --no-sanitize-hostnames" > ${output_file}
  if [ -s ${output_file} ]; then
    msg "${GREEN}Input file, ${input_file}, sanitized and written to ${output_file}${NOFORMAT}."
    exit 0
  else
    die "${RED}Error writing to output file, ${output_file}!${NOFORMAT}"
  fi
fi
