#!/bin/bash
# Based upon: https://tipstricks.itmatrix.eu/blocking-all-traffic-from-individual-countries-using-ipset-and-iptables/
# Purpose: Sends the blocked traffic report per email and resets the counter
# Syntax: sudo ./country-firewall-report.sh
# Dependencies: Systems tools: iptables, awk, column, whois, sendmail
#----------------------------------------------------------
#
# Cron entry: @daily /bin/bash -c ". /home/centos/.bashrc ; /home/centos/country-firewall-report.sh"
#

HOST=$(cat /etc/hostname | tr 'a-z' 'A-Z')
email="email@domain.com"
reportsender="cron@$HOST"
subject="BLOCKED Packets report on $(hostname | tr 'a-z' 'A-Z')"
tempdir="/tmp"
file1="iptables_report1.txt"
file2="iptables_report2.txt"

#------------ Build the header of the mail to send ------------
echo "From: $reportsender" > $tempdir/$file1
echo "To: $email" >> $tempdir/$file1
echo "Subject: $subject" >> $tempdir/$file1
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
