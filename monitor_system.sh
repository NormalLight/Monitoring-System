#!/bin/bash

# Monitoring and Alerting System Script

ALERT_EMAIL=""  # Mandatory argument: Email address used for receiving alerts
CPU_THRESHOLD=90   # Default Threshold for CPU usage in percentage
MEM_THRESHOLD=90   # Default Threshold for memory usage in percentage
DISK_THRESHOLD=80  # Default Threshold for disk usage in percentage
MONITOR_LOG_FILE="/var/log/syslog"  # Path to system log file for monitoring
NETWORK_THRESHOLD=1000000  # Default Threshold for network usage in bytes/sec
SERVICES=("apache2" "mysql") # Default Services to monitor
CRON_INTERVAL="* * * * *"  # Default Cron schedule to run the script every minute
CRON_LOG_FILE="/home/ethan/SystemsProject/monitor_log.log"  # Log file for cron job output
SCRIPT_PATH="$(realpath "$0")"  # Full path to this script for cron job

# Function to display usage instructions
usage() {
  echo "Usage: $0 -e <alert_email> [-c <cpu_threshold>] [-m <mem_threshold>] [-d <disk_threshold>] [-n <network_threshold>] [-i <cron_interval>] [-s <services>] [-u] [-t]"
  echo
  echo "Options:"
  echo "  -e    Email address for alerts (mandatory)"
  echo "  -c    CPU usage threshold (default: $CPU_THRESHOLD)"
  echo "  -m    Memory usage threshold (default: $MEM_THRESHOLD)"
  echo "  -d    Disk usage threshold (default: $DISK_THRESHOLD)"
  echo "  -n    Network usage threshold in bytes/sec (default: $NETWORK_THRESHOLD)"
  echo "  -i    Cron interval (default: \"$CRON_INTERVAL\")"
  echo "  -s    Comma-separated list of services to monitor (default: ${SERVICES[*]})"
  echo "  -u    Display usage information"
  echo "  -t    Turn off the script by removing its cron job"
  exit 2 # Invalid arguments
}

# Parse command-line arguments using getopts
TURN_OFF=0  # Flag to check if the -t option is passed
while getopts "e:c:m:d:n:i:s:tu" opt; do
  case $opt in
    e) ALERT_EMAIL="$OPTARG" ;;    # Set the alert email (mandatory)
    c) CPU_THRESHOLD="$OPTARG" ;; # Set the CPU threshold
    m) MEM_THRESHOLD="$OPTARG" ;; # Set the memory threshold
    d) DISK_THRESHOLD="$OPTARG" ;; # Set the disk threshold
    n) NETWORK_THRESHOLD="$OPTARG" ;; # Set the network threshold
    i) CRON_INTERVAL="$OPTARG" ;; # Set the cron interval
    s) IFS=',' read -r -a SERVICES <<< "$OPTARG" ;; # Parse services into an array
    t) TURN_OFF=1 ;;  # Set the turn-off flag
    u) usage ;;  # Display usage and exit
    *) usage ;; # Display usage instructions on invalid options
  esac
done

# Check if mandatory argument is provided unless turning off or displaying usage
if [[ $TURN_OFF -eq 0 && $OPTARG != "-u" && -z "$ALERT_EMAIL" ]]; then
  echo "Error: Alert email is required."
  usage
fi

# Function to stop the cron job
stop_cron() {
  echo "Turning off the script and removing its cron job..."
  # Remove the script's cron job by filtering it out from the crontab
  crontab -l | grep -v "$SCRIPT_PATH" | crontab -
  echo "Cron job removed. Monitoring script is now turned off."
  exit 0
}

# Ensures the log file exists and is writable
check_file_writable() {
  local file=$1
  # Create the file if it doesn't exist
  if [[ ! -e $file ]]; then
    echo "File $file does not exist. Creating it..."
    touch "$file" || { echo "Error: Unable to create $file. Exiting."; exit 1; }
  elif [[ ! -w $file ]]; then
    # Exit if the file exists but is not writable
    echo "Error: File $file is not writable. Exiting."
    exit 1
  fi
}

# Handles errors from critical commands
handle_command_error() {
  local cmd="$1"
  # Check the exit status of the last command and exit if it failed
  if [[ $? -ne 0 ]]; then
    echo "Error: Command '$cmd' failed. Exiting."
    exit 3
  fi
}

# Function to monitor CPU usage
monitor_cpu() {
  echo "Monitoring CPU usage..."
  # Retrieve CPU usage using top and calculate %user + %system
  local cpu_usage=$(top -b -n1 | grep "Cpu(s)" | awk '{print $2 + $4}')
  handle_command_error "top"  # Handle errors from top command
  echo "Current CPU usage: $cpu_usage%"
  # Compare CPU usage with the threshold and send an alert if exceeded
  if (( $(echo "$cpu_usage > $CPU_THRESHOLD" | bc -l) )); then
    send_alert "High CPU usage: $cpu_usage%"
  fi
}

# Function to monitor Memory usage
monitor_memory() {
  echo "Monitoring Memory usage..."
  # Retrieve memory usage as a percentage of total memory
  local mem_usage=$(free | awk '/Mem/{printf("%.2f"), $3/$2 * 100.0}')
  handle_command_error "free"  # Handle errors from free command
  echo "Current Memory usage: $mem_usage%"
  # Compare memory usage with the threshold and send an alert if exceeded
  if (( $(echo "$mem_usage > $MEM_THRESHOLD" | bc -l) )); then
    send_alert "High Memory usage: $mem_usage%"
  fi
}

# Function to monitor Disk usage
monitor_disk() {
  echo "Monitoring Disk usage..."
  # Retrieve disk usage for the root directory
  local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
  handle_command_error "df"  # Handle errors from df command
  echo "Current Disk usage: $disk_usage%"
  # Compare disk usage with the threshold and send an alert if exceeded
  if (( disk_usage > $DISK_THRESHOLD )); then
    send_alert "High Disk usage: $disk_usage%"
  fi
}

# Function to monitor logs for errors or warnings
monitor_logs() {
  echo "Monitoring logs for errors or warnings..."
  # Check if the log file exists; if not, skip log monitoring
  if [[ ! -e $MONITOR_LOG_FILE ]]; then
    echo "Log file $MONITOR_LOG_FILE does not exist. Skipping log monitoring."
    return
  fi
  # Retrieve the last 5 error or warning lines from the log file
  local errors=$(grep -Ei "error|warn" $MONITOR_LOG_FILE | tail -n 5)
  # Send an alert if any errors or warnings are found
  if [[ ! -z "$errors" ]]; then
    send_alert "Log alerts:\n$errors"
  fi
}

# Function to monitor specific services
monitor_service() {
  local failed_services=()  # Array to store failed services
  for service in "${SERVICES[@]}"; do
    echo "Checking status of service: $service"
    if systemctl is-active --quiet "$service"; then
      echo "Service $service is running."
    else
      failed_services+=("$service")  # Add the service to the failed list
    fi
  done

  # Send a single alert for all failed services
  if [[ ${#failed_services[@]} -gt 0 ]]; then
    # Build a single message with all failed services
    local message="The following services are not active:\n"
    for service in "${failed_services[@]}"; do
      message+="$service\n"  # Append each service to the message
    done
    send_alert "$(echo -e "$message")"  # Send consolidated alert with proper formatting
  fi
}


# Function to detect the default network interface
detect_network_interface() {
  # Retrieve the default network interface
  local default_iface=$(ip route | awk '/default/ {print $5}')
  handle_command_error "ip route"  # Handle errors from ip route command
  if [[ -z "$default_iface" ]]; then
    echo "No active network interface detected. Exiting."
    exit 1
  fi
  echo $default_iface
}

# Function to monitor network usage
monitor_network() {
  local iface=$(detect_network_interface)
  echo "Monitoring network usage on interface: $iface..."
  # Retrieve received and transmitted bytes before a 1-second delay
  local rx_before=$(cat /sys/class/net/$iface/statistics/rx_bytes)
  local tx_before=$(cat /sys/class/net/$iface/statistics/tx_bytes)
  sleep 1
  local rx_after=$(cat /sys/class/net/$iface/statistics/rx_bytes)
  local tx_after=$(cat /sys/class/net/$iface/statistics/tx_bytes)
  # Calculate the rate of received and transmitted bytes
  local rx_rate=$((rx_after - rx_before))
  local tx_rate=$((tx_after - tx_before))
  echo "Receive rate: $rx_rate bytes/sec, Transmit rate: $tx_rate bytes/sec"
  # Compare rates with the threshold and send an alert if exceeded
  if (( rx_rate > NETWORK_THRESHOLD || tx_rate > NETWORK_THRESHOLD )); then
    send_alert "High network usage detected: RX=$rx_rate bytes/sec, TX=$tx_rate bytes/sec"
  fi
}

# Setups up cron job
setup_cron() {
  echo "Setting up cron job..."
  # Check if the cron job already exists
  crontab -l | grep -F "$SCRIPT_PATH" &> /dev/null
  if [[ $? -eq 0 ]]; then
    echo "Cron job already exists. Skipping setup."
  else
    # Add the script to the user's crontab with the specified interval
    (crontab -l 2>/dev/null; echo "$CRON_INTERVAL $SCRIPT_PATH -e $ALERT_EMAIL -c $CPU_THRESHOLD -m $MEM_THRESHOLD -d $DISK_THRESHOLD -n $NETWORK_THRESHOLD -s \"${SERVICES[*]}\" >> $CRON_LOG_FILE 2>&1") | crontab -
    echo "Cron job added with interval: $CRON_INTERVAL"
  fi
}

# Function to send alerts
send_alert() {
  local message=$1
  echo "Sending alert: $message"
  # Use mail to send the alert
  echo -e "$message" | mail -s "System Alert" $ALERT_EMAIL
  if [[ $? -ne 0 ]]; then
    echo "Error: Failed to send email alert."
  fi
}

# Main Function
main() {
  # Check if the script should be turned off
  if [[ $TURN_OFF -eq 1 ]]; then
    stop_cron
  fi

  check_file_writable "$CRON_LOG_FILE"
  echo "Starting Monitoring System..."
  setup_cron
  echo
  monitor_cpu
  echo
  monitor_memory
  echo
  monitor_disk
  echo
  monitor_network
  echo
  monitor_service
  echo
  monitor_logs
  echo
}

# Trap unexpected errors
trap 'echo "An unexpected error occurred. Exiting..." ; exit 1;' ERR

# Execute the main function
main

