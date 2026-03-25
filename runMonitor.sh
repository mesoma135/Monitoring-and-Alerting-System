#!/bin/bash

# Move into the current script directory
cd "$(dirname "$0")"

# Run data collection
./collect_metrics.sh

# Wait 10 seconds
sleep 10

# Run threshold checker (writes threshold_output.txt in the same directory)
./thresholdChecker.sh > threshold_output.txt

# Wait 2 seconds
sleep 2

# Run alert processing
./alertingMech.sh
