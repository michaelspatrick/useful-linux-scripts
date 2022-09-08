#!/bin/bash
# Script backups some /etc files and directories that I want to keep a backup of

BACKUPDIR="/BACKUPS/etc"
DATETIME=`date +%F`
MY_S3_BUCKET="BUCKETNAME"
MY_S3_FOLDER="BUCKETFOLDER"
NICE="nice -n 19 ionice -c2 -n 7"

sudo sh -c "tar -cz /etc/httpd > ${BACKUPDIR}/${DATETIME}_httpd.tgz"
sudo sh -c "tar -cz /etc/fail2ban > ${BACKUPDIR}/${DATETIME}_fail2ban.tgz"
sudo sh -c "tar -cz /etc/redis > ${BACKUPDIR}/${DATETIME}_redis.tgz"
sudo sh -c "tar -cz /etc/postfix > ${BACKUPDIR}/${DATETIME}_postfix.tgz"
sudo sh -c "cp /etc/my.cnf ${BACKUPDIR}/${DATETIME}_my.cnf; gzip ${BACKUPDIR}/${DATETIME}_my.cnf"
sudo sh -c "cp /etc/php.ini ${BACKUPDIR}/${DATETIME}_php.ini; gzip ${BACKUPDIR}/${DATETIME}_php.ini"

# Sync backups to the Amazon S3 Bucket
sudo nice -n 19 s3cmd -v sync ${BACKUPDIR} s3://${MY_S3_BUCKET}/${MY_S3_FOLDER}/ --delete-removed > ${BACKUPDIR}/${DATETIME}_s3-sync.log 2>&1
