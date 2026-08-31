#!/usr/bin/env bash
# Probe which fan speed values produce distinct RPMs.
# Run with the cooler ON (medium mode) before starting.
# Usage: ./probe_fan.sh

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS_FILE="$HOME/.cooler_status.json"
CMD_FILE="$HOME/.cooler_cmd.json"

SETTLE=3   # seconds to wait after each write for RPM to stabilise

rpm_now() {
    python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('fan_rpm','?'))" 2>/dev/null || echo "?"
}

send_fan() {
    printf '{"fan_speed":%d}' "$1" > "$CMD_FILE"
}

# Make sure the app is running and cooler is on
if [[ ! -f "$HOME/.cooler.pid" ]]; then
    echo "RedMagic Cooler app doesn't appear to be running. Start it first."
    exit 1
fi

echo "Turning cooler ON (medium) to keep TEC active…"
printf '{"cooling_mode":2,"auto_mode":false}' > "$CMD_FILE"
sleep 2

printf '\n%-12s  %10s\n' "fan_speed %" "RPM"
printf '%-12s  %10s\n' "------------" "----------"

for pct in 0 5 10 15 20 25 30 33 40 50 60 66 70 75 80 90 100; do
    send_fan "$pct"
    sleep "$SETTLE"
    rpm=$(rpm_now)
    printf '%-12s  %10s\n' "${pct}%" "$rpm"
done

echo ""
echo "Done. Restore auto mode with: ./cooler auto"
