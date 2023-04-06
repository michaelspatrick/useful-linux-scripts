#!/bin/sh

# This script uses pt-secure-collect from the Percona Toolkit to sanitize SQL statements in a text file.
# The original tool requires there be a ";" at the end of each line.
# Thanks to Michael Benshoof for providing the regex which is used with a sed command to append a semicolon to each SQL statement.
# This effectively solves the problem for output from SHOW ENGINE INNODB STATUS.

if ! command -v pt-secure-collect &> /dev/null
then
    echo "The utility, pt-secure-collect, does not exist.  Please install the latest version of the Percona Toolkit."
    exit 1
fi

if [ $# -eq 0 ]
  then
    echo "Missing filename."
    echo "Usage: $0 <textfile>"
    exit 1
fi

sed -r '/^(INSERT|UPDATE|SELECT|DELETE)/ s/$/;/' $1 | pt-secure-collect sanitize --no-sanitize-hostnames

exit 0
