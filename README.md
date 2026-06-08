# Linux System Monitoring and Alerting Script

A simple Bash monitoring script for Linux systems. The script checks CPU usage, memory usage, disk usage, network usage, service status, and system logs, then sends email alerts when configured thresholds are exceeded.

This script was developed and used on **Ubuntu Linux**. It should also work on many other Linux distributions that use common GNU/Linux tools and `systemd`, such as Debian, Linux Mint, Fedora, or similar distributions, though package names and log file locations may vary.

## Features

- Monitors CPU usage
- Monitors memory usage
- Monitors root disk usage
- Monitors network receive/transmit usage
- Checks selected services, such as Apache and MySQL
- Scans the system log for errors and warnings
- Sends email alerts when thresholds are exceeded
- Can install itself as a cron job for repeated monitoring
- Can remove its cron job using the turn-off option

## Requirements

The script uses standard Linux command-line tools, including:

- `bash`
- `top`
- `free`
- `df`
- `ip`
- `systemctl`
- `grep`
- `awk`
- `sed`
- `bc`
- `cron`
- `mail`

On Ubuntu, you may need to install missing dependencies:

```bash
sudo apt update
sudo apt install bc mailutils cron
```

The script also assumes that the services being monitored are managed by `systemd`.

## Setup

Make the script executable:

```bash
chmod +x monitor_system.sh
```

Run the script with an alert email address:

```bash
./monitor_system.sh -e your_email@example.com
```

The email address is required because alerts are sent using the `mail` command.

## Usage

```bash
./monitor_system.sh -e <alert_email> [options]
```

### Options

| Option | Description |
|---|---|
| `-e` | Email address for alerts. Required unless turning off the script. |
| `-c` | CPU usage threshold percentage. Default: `90` |
| `-m` | Memory usage threshold percentage. Default: `90` |
| `-d` | Disk usage threshold percentage. Default: `80` |
| `-n` | Network usage threshold in bytes per second. Default: `1000000` |
| `-i` | Cron interval. Default: `* * * * *` |
| `-s` | Comma-separated list of services to monitor. Default: `apache2,mysql` |
| `-u` | Display usage information |
| `-t` | Turn off the script by removing its cron job |

## Examples

Run with default thresholds:

```bash
./monitor_system.sh -e admin@example.com
```

Run with custom CPU, memory, and disk thresholds:

```bash
./monitor_system.sh -e admin@example.com -c 85 -m 80 -d 75
```

Monitor different services:

```bash
./monitor_system.sh -e admin@example.com -s nginx,ssh
```

Run every 5 minutes using cron:

```bash
./monitor_system.sh -e admin@example.com -i "*/5 * * * *"
```

Turn off the scheduled cron job:

```bash
./monitor_system.sh -t
```

## What the Script Monitors

### CPU Usage

The script checks current CPU usage using `top`. If usage is above the configured CPU threshold, an alert email is sent.

### Memory Usage

The script checks used memory as a percentage of total memory using `free`. If usage is above the configured memory threshold, an alert email is sent.

### Disk Usage

The script checks disk usage for the root directory `/` using `df`. If usage is above the configured disk threshold, an alert email is sent.

### Network Usage

The script automatically detects the default network interface using `ip route`, then measures received and transmitted bytes over one second. If either value exceeds the configured network threshold, an alert email is sent.

### Service Status

The script checks whether selected services are active using `systemctl`. If any monitored service is not running, an alert email is sent.

### System Logs

The script checks `/var/log/syslog` for recent lines containing `error` or `warn`. If matching log entries are found, an alert email is sent.

> Note: Some Linux distributions may use a different system log location. For example, some systems rely more heavily on `journalctl` instead of `/var/log/syslog`.

## Cron Job Behaviour

When the script is run, it attempts to add itself to the current user's crontab using the configured interval. By default, it runs once per minute.

The script logs cron output to:

```bash
/home/ethan/SystemsProject/monitor_log.log
```

If using this script on another machine, update the log file path inside the script if needed.

## Notes

- The script may require permission to read system logs or write to the configured cron log file.
- Email alerts require a working local mail setup.
- Service names may differ between Linux distributions. For example, Apache may be called `apache2` on Ubuntu/Debian but `httpd` on Fedora/RHEL.
- The default monitored services are `apache2` and `mysql`.
- The default monitored system log is `/var/log/syslog`, which is common on Ubuntu-based systems.


