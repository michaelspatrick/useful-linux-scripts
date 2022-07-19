#!/bin/sh
#
# Simple bash script that runs and waits for a PID to terminate and then executes a command.
#
# To have the script email when a job is complete for example, do something like this:
#
# ./waitforpid.sh 24380 "echo 'Job complete on vmlit51092' | mail -s 'Job Complete' someone@domain.com"
#

#Grab the parameter off the command line delay=5
delay=5
pid=$1
cmd=$2
usage=0;

if [ "$pid" == "" ]; then
  usage=1;
  echo "PID is required"
fi

if [ "$usage" == "1" ]; then
  echo "usage: waitforpid.sh PID CMD"
  echo " where"
  echo " PID = Process id to wait for"
  echo " COMMAND = Command to be executed after it completes"
  exit
fi

if [ "$cmd" == "" ]; then
  usage=1;
  echo "COMMAND is required"
fi

#Redirect stdout and stderr of the ps command to /dev/null
ps -p$pid 2>&1 > /dev/null

#Grab the status of the ps command
status=$?