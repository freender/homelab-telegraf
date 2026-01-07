#!/bin/bash
# Deploy Telegraf Monitoring to Cluster
# Usage: ./deploy.sh [host1 host2 ...] or ./deploy.sh all

set -e

HOSTS="${@:-ace bray clovis xur}"
if [[ "$1" == "all" ]]; then
    HOSTS="ace bray clovis xur"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_CONFIG="${SCRIPT_DIR}/telegraf.conf"
SENSORS_CONFIG="${SCRIPT_DIR}/sensors.conf"
SMARTCTL_CONFIG="${SCRIPT_DIR}/smartctl.conf"
DISKIO_CONFIG="${SCRIPT_DIR}/diskio.conf"
NET_CONFIG="${SCRIPT_DIR}/net.conf"

if [[ ! -f "$MAIN_CONFIG" ]]; then
    echo "Error: telegraf.conf not found at $MAIN_CONFIG"
    exit 1
fi

echo "==> Deploying Telegraf Monitoring"
echo "    Hosts: $HOSTS"
echo "    Collection Interval: 10s (sensors), 10s (smartctl), 10s (diskio)"
echo ""

for host in $HOSTS; do
    echo "==> Deploying to $host..."

    # Add InfluxData repository if not present
    if ! ssh "$host" "test -f /etc/apt/sources.list.d/influxdata.list"; then
        echo "    Adding InfluxData repository..."
        ssh "$host" "curl -fsSL https://repos.influxdata.com/influxdata-archive_compat.key | gpg --dearmor -o /etc/apt/keyrings/influxdata-archive.gpg"
        ssh "$host" "echo 'deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' | tee /etc/apt/sources.list.d/influxdata.list"
        ssh "$host" "apt-get update -qq"
    else
        echo "    InfluxData repository already configured"
    fi

    # Install required packages
    echo "    Installing packages (telegraf, lm-sensors, smartmontools)..."
    ssh "$host" "apt-get update -qq && apt-get install -y telegraf lm-sensors smartmontools"

    # Ensure lm-sensors is configured
    echo "    Configuring lm-sensors..."
    ssh "$host" "sensors-detect --auto >/dev/null 2>&1 || true"

    # Deploy main configuration
    echo "    Deploying telegraf.conf..."
    scp "$MAIN_CONFIG" "${host}:/etc/telegraf/telegraf.conf"
    ssh "$host" "chown root:root /etc/telegraf/telegraf.conf && chmod 644 /etc/telegraf/telegraf.conf"

    # Ensure telegraf.d directory exists
    ssh "$host" "mkdir -p /etc/telegraf/telegraf.d"

    # Deploy sensors configuration
    echo "    Deploying sensors.conf..."
    scp "$SENSORS_CONFIG" "${host}:/etc/telegraf/telegraf.d/sensors.conf"
    ssh "$host" "chown root:root /etc/telegraf/telegraf.d/sensors.conf && chmod 644 /etc/telegraf/telegraf.d/sensors.conf"

    # Deploy smartctl configuration (inputs.smartctl)
    if [[ -f "$SMARTCTL_CONFIG" ]]; then
        echo "    Deploying smartctl.conf..."
        scp "$SMARTCTL_CONFIG" "${host}:/etc/telegraf/telegraf.d/smartctl.conf"
        ssh "$host" "chown root:root /etc/telegraf/telegraf.d/smartctl.conf && chmod 644 /etc/telegraf/telegraf.d/smartctl.conf"

        # Deploy sudoers rule for smartctl
        echo "    Deploying sudoers rule for smartctl..."
        scp "${SCRIPT_DIR}/telegraf-smartctl-sudoers" "${host}:/etc/sudoers.d/telegraf-smartctl"
        ssh "$host" "chown root:root /etc/sudoers.d/telegraf-smartctl && chmod 440 /etc/sudoers.d/telegraf-smartctl"
    fi

    # Deploy diskio configuration

    # Deploy net configuration
    if [[ -f "$NET_CONFIG" ]]; then
        echo "    Deploying net.conf..."
        scp "$NET_CONFIG" "${host}:/etc/telegraf/telegraf.d/net.conf"
        ssh "$host" "chown root:root /etc/telegraf/telegraf.d/net.conf && chmod 644 /etc/telegraf/telegraf.d/net.conf"
    fi
    if [[ -f "$DISKIO_CONFIG" ]]; then
        echo "    Deploying diskio.conf..."
        scp "$DISKIO_CONFIG" "${host}:/etc/telegraf/telegraf.d/diskio.conf"
        ssh "$host" "chown root:root /etc/telegraf/telegraf.d/diskio.conf && chmod 644 /etc/telegraf/telegraf.d/diskio.conf"
    fi

    # Remove any old processor normalizers
    ssh "$host" "rm -f /etc/telegraf/telegraf.d/processors-smartctl.conf"

    # Enable and restart telegraf
    echo "    Enabling and restarting telegraf service..."
    ssh "$host" "systemctl enable telegraf && systemctl restart telegraf"

    # Check status
    echo "    Checking service status..."
    if ssh "$host" "systemctl is-active --quiet telegraf"; then
        echo "    ✓ Telegraf running on $host"
    else
        echo "    ✗ Warning: Telegraf not running on $host"
        ssh "$host" "systemctl status telegraf --no-pager -l" || true
    fi

    echo ""
done

echo "==> Deployment complete!"
