#!/bin/bash
# Simple script to backup MySQL databases using mysqldump to individual files per database.
# Script also writes all databases to a single dump file
# MySQL credentials are stored using mysql_config_editor command

# Set these variables
BACKUPDIR="/BACKUPS"
MY_S3_BUCKET="BUCKETNAME"
MY_S3_FOLDER="FOLDERNAME"

# Generated Variables
DATETIME=`date +%F`
DAY="$(date +%a)"
BACKUP_PREFIX="${BACKUPDIR}/${DATETIME}"
NICE="nice -n 10 ionice -c2 -n 7"
MYSQL="mysql --login-path=local"
MYSQLDUMP="nice -n 10 ionice -c2 -n 7 mysqldump --login-path=local -c --single-transaction --quick"

# Cleanup Old Files
find /BACKUPS/* -mtime +6 -exec rm {} \;

${MYSQL} -e "show databases" | grep -Ev 'Database|information_schema|performance_schema|sys' | while read dbname;
do
  BACKUP_FILE="${BACKUPDIR}/${DATETIME}_$dbname.sql"
  echo "Dumping $dbname to ${BACKUP_FILE}"
  ${MYSQLDUMP} $dbname > ${BACKUP_FILE} && ${NICE} gzip -f ${BACKUP_FILE}
done

# Backup All MySQL Databases
BACKUP_ALL="${BACKUP_PREFIX}_all.sql"
echo "Dumping all databases to ${BACKUP_ALL}"
${MYSQLDUMP} --all-databases > ${BACKUP_ALL} && ${NICE} gzip -f ${BACKUP_ALL}

# Sync backups to the Amazon S3 Bucket
#${NICE} s3cmd -v sync ${BACKUPDIR} s3://${MY_S3_BUCKET}/${MY_S3_FOLDER}/ --delete-removed > ${BACKUP_PREFIX}_s3-sync.log 2>&1
