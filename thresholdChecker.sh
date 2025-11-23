#!/bin/bash

METRICS_FILE="/tmp/system_metrics.json"

#---Defining Thresholds ---
CPU_THRESHOLD=90
MEM_THRESHOLD=85
DISK_THRESHOLD=80
STD_THRESHOLD=5

#---Checking for JSON file---
if [! -f"$METRICS_FILE"]; then
echo "ERROR: Metrics file not found"
exit 1
fi

#---Parsing JSON file---
cpu=$(jq '.cpu' $METRICS_FILE)
memory=$(jq, '.memory' $METRICS_FILE)
disk=$(jq '.disk' $METRICS_FILE)
errors=$(jq '.errors' $METRICS_FILE)

#---Threshold CHeck Function---
check_threshold(){
value=$1
threshold=$2
name=$3

if(($(echo "$value > $threshold" | bc -1))); then
echo "ALERT_${name}_HIGH:$value"
else
echo "OK_${name}:$value"
fi
}

#---Threshold Checks---
check_threshold "$cpu" "$CPU_THRESHOLD" "CPU"
check_threshold "memory" "$MEM_THRESHOLD" "MEMORY"
check_threshold "$disk" "DISK_THRESHOLD" "DISK"

#---Anomaly Detection with a sliding window of 5---
HISTORY_FILE="/tmp/error_history.txt"

#Create the file if not found in directory
touch $HISTORY_FILE

#Append new value
echo "$errors" >> $HISTORY_FILE

tail -n 5 $HISTORY_FILE > /tmp/tmp_history
mv /tmp/tmp_history $HISTORY_FILE

#Calculate the mean
mean=$(awk '{sum+=$1} END {if (NR>0)print sum/NR;else print 0}' $HISTORY_FILE)

#Detect spikes
if ((errors > mean + STD_THRESHOLD )); then
echo "ANOMALY_ERROR_SPIKE:true"
else
echo "ANOMALY_ERROR_SPIKE:false"
fi
