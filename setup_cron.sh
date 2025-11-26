#!/bin/bash

echo "=== Monitoring System Setup Starting ==="

# Default project root (where your scripts are)
PROJECT_ROOT="$HOME/systemsProject/projectNew"

echo "Using project directory: $PROJECT_ROOT"

# Ensure directory exists
mkdir -p "$PROJECT_ROOT"

# Make all scripts executable
chmod +x "$PROJECT_ROOT"/*.sh 2>/dev/null

# Create a wrapper script that cron will run with relative paths
WRAPPER="$PROJECT_ROOT/run_monitor.sh"

cat << 'EOF' > "$WRAPPER"
#!/bin/bash

# Change to the directory where this script lives
cd "$(dirname "$0")"

# Relative script paths
./collect_metrics.sh
sleep 10
./thresholdChecker.sh > "$HOME/threshold_output.txt"
sleep 2
./alertingMech.sh
EOF

chmod +x "$WRAPPER"

echo "Wrapper script created at: $WRAPPER"

# Install crontab entries (every 30 seconds)
CRON_FILE="$PROJECT_ROOT/cronjob.tmp"

cat << EOF > "$CRON_FILE"
# === MONITORING SYSTEM CRON JOBS (EVERY 30 SECONDS) ===

# Run immediately at minute start
* * * * * bash $WRAPPER >> $HOME/cron.log 2>&1

# Run again 60 seconds later
* * * * * sleep 60 && bash $WRAPPER >> $HOME/cron.log 2>&1
EOF

# Install the cron job
crontab "$CRON_FILE"
rm "$CRON_FILE"

echo "Cron jobs installed."
echo "=== Monitoring System Setup Complete ==="

