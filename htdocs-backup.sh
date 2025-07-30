#!/bin/bash
# Script performs backups of websites to individual files

# Set these variables
BACKUPDIR="/BACKUPS/WEBSITES"
HTDOCSDIR="/var/www"
MY_S3_BUCKET="BUCKETNAME"
MY_S3_FOLDER="FOLDERAME"

# Calculate some variables
DATETIME=`date +%F`
DAY="$(date +%a)"
NICE="nice -n 19 ionice -c2 -n 7"

# Cleanup Old Files
find ${BACKUPDIR} -mtime +6 -exec rm {} \;

# Backup HTDOCS
for dir in ${HTDOCSDIR}/*/
do
  dir=${dir%*/}      # remove the trailing "/"
  DIRNAME="${dir##*/}"
  echo "Backing up ${HTDOCSDIR}/${DIRNAME} to ${BACKUPDIR}/${DATETIME}_${DIRNAME}.tgz"
  sudo sh -c "${NICE} tar fcz ${BACKUPDIR}/${DATETIME}_${DIRNAME}.tgz -C ${HTDOCSDIR} ${DIRNAME}"
done

# Sync backups to the Amazon S3 Bucket
sudo nice -n 19 s3cmd -v sync ${BACKUPDIR} s3://${MY_S3_BUCKET}/${MY_S3_FOLDER}/ --delete-removed > ${BACKUPDIR}/${DATETIME}_s3-sync.log 2>&1
