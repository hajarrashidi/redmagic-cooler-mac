#!/usr/bin/env bash
# Probe all 8 cooling mode bytes and measure hot-side temperature for each.
# Fan is held at max (value 100) throughout to isolate the TEC effect.
# Takes ~5 minutes total — each mode gets 30 s to stabilise.

set -euo pipefail

STATUS_FILE="$HOME/.cooler_status.json"
CMD_FILE="$HOME/.cooler_cmd.json"
SETTLE=45

if [[ ! -f "$HOME/.cooler.pid" ]]; then
    echo "RedMagic Cooler app doesn't appear to be running. Start it first."
    exit 1
fi

read_field() {
    python3 -c "import json; d=json.load(open('$STATUS_FILE')); print(d.get('$1','?'))" 2>/dev/null || echo "?"
}

send_raw_mode() {
    # Write cooling_mode and fan_speed directly; auto_mode=false keeps autopilot off
    printf '{"cooling_mode":%d,"fan_speed":100,"auto_mode":false}' "$1" > "$CMD_FILE"
}

echo "Holding fan at max (value 100) throughout to isolate TEC."
echo "Each mode gets ${SETTLE}s to stabilise. Total ~$((8 * SETTLE))s."
echo ""
printf '%-14s  %8s  %8s  %8s  %8s\n' "mode" "cold_c" "hot_c" "ambient" "mac_cpu"
printf '%-14s  %8s  %8s  %8s  %8s\n' "--------------" "--------" "--------" "--------" "--------"

for mode in 3 1 4 5 2 6 7 8; do
    send_raw_mode "$mode"
    sleep "$SETTLE"
    cold=$(read_field cold_c)
    hot=$(read_field hot_c)
    ambient=$(read_field ambient_c)
    cpu=$(read_field cpu_c)
    case $mode in
        3) label="(OFF)" ;;
        1) label="(Low)" ;;
        2) label="(Medium)" ;;
        8) label="(Max)" ;;
        *) label="(unlisted)" ;;
    esac
    printf '0x%02X %-9s  %8s  %8s  %8s  %8s\n' "$mode" "$label" "$cold" "$hot" "$ambient" "$cpu"
done

echo ""
echo "Restoring auto mode…"
printf '{"auto_mode":true}' > "$CMD_FILE"
echo "Done."
