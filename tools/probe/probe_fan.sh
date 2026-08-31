#!/usr/bin/env bash
# Probe which fan speed values produce distinct RPMs.
# Run with the cooler ON (medium mode) before starting.
# Usage: ./probe_fan.sh

set -euo pipefail

STATUS_FILE="$HOME/.redmagic_probe_status.json"
CMD_FILE="$HOME/.redmagic_probe_command.json"

SETTLE=3   # seconds to wait after each write for RPM to stabilise

rpm_now() {
    python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('fan_rpm','?'))" 2>/dev/null || echo "?"
}

send_fan() {
    printf '{"fan_speed":%d}' "$1" > "$CMD_FILE"
}

# Make sure a fresh, connected probe-enabled build is running.
if [[ ! -f "$STATUS_FILE" ]] || ! python3 -c \
    "import json,time; d=json.load(open('$STATUS_FILE')); assert d.get('connected') and time.time()-d.get('ts',0)<5" \
    2>/dev/null; then
    echo "No connected probe build found. Run ./build.sh --with-probes --run first."
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
echo "Restoring auto mode…"
printf '{"auto_mode":true}' > "$CMD_FILE"
echo "Done."
