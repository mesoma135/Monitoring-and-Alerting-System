#!/bin/bash

# Configuration

PROJ_DIR="$(dirname "$0")"
THRESHOLD_OUTPUT="$PROJ_DIR/threshold_output.txt"
ALERT_LOG="$PROJ_DIR/system_alerts.log"
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS:-m.tarun1012@gmail.com}"
HOSTNAME="$(hostname)"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# email alert - This does not currently run as there is an accessibility issue
send_email() {
  local subject="$1"
  local message="$2"
  
  # Check if mail command exists
  if ! command -v mail >/dev/null 2>&1; then
    print_alert "WARNING" "mail command not found. Email not sent."
    return 1
  fi
  
  # Send email
  echo "$message" | mail -s "$subject" "$EMAIL_RECIPIENTS" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    print_alert "EMAIL" "Alert sent to $EMAIL_RECIPIENTS"
  else
    print_alert "ERROR" "Failed to send email to $EMAIL_RECIPIENTS"
    return 1
  fi
}

# log alerts within a file
log_alert() {
  local message="$1"
  
  mkdir -p "$PROJ_DIR" 2>/dev/null
  echo "[$TIMESTAMP] [$HOSTNAME] $message" >> "$ALERT_LOG"
}

# Output within the console
print_alert() {
  local alert_type="$1"
  local message="$2"
  
  echo "[$(date '+%H:%M:%S')] $alert_type: $message"
}

# Process alerts
process_alerts() {
  if [ ! -f "$THRESHOLD_OUTPUT" ]; then
    print_alert "ERROR" "Threshold output file not found: $THRESHOLD_OUTPUT"
    return 1
  fi
  alert_count=0 
  while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue  
    # Check for ALERT_ prefix
    if [[ "$line" == ALERT_* ]]; then
      alert_count=$((alert_count + 1))    
      # Extract metric name and value
      metric=$(echo "$line" | cut -d'_' -f2- | cut -d':' -f1)
      value=$(echo "$line" | cut -d':' -f2)
     
      # Create alert message
      alert_msg="THRESHOLD ALERT
Hostname: $HOSTNAME
Metric: $metric
Value: $value
Time: $TIMESTAMP"
      
      # Print to console
      print_alert "THRESHOLD ALERT" "$metric exceeded - Value: $value"   
      # Log to file
      log_alert "THRESHOLD ALERT - $metric: $value" 
      # Send email
      send_email "[ALERT] $metric High on $HOSTNAME" "$alert_msg"
      
    # Check for anomaly detection
    elif [[ "$line" == ANOMALY_* ]]; then
      anomaly=$(echo "$line" | cut -d':' -f1)
      status=$(echo "$line" | cut -d':' -f2) 
      if [ "$status" = "true" ]; then
        alert_count=$((alert_count + 1))
        # Create alert message
        alert_msg="ANOMALY DETECTED
Hostname: $HOSTNAME
Type: $anomaly
Time: $TIMESTAMP"    
        # Print to console
        print_alert "ANOMALY ALERT" "$anomaly detected"
        
        # Log to file
        log_alert "ANOMALY ALERT - $anomaly: true"
        
        # Send email
        send_email "[ANOMALY] $anomaly on $HOSTNAME" "$alert_msg"
      fi
    fi
  done < "$THRESHOLD_OUTPUT"
  return 0
}

#main
echo "========================================"
echo "Starting Alert Processing..."
echo "========================================"

process_alerts

echo "========================================"
echo "Alert Processing Complete"
echo "Log file: $ALERT_LOG"
echo "========================================"
