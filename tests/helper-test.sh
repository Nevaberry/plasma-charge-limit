#!/bin/bash
# Tests the widget's helper script against a fake /sys/class/power_supply.
# Usage: tests/helper-test.sh
set -euo pipefail
export LC_ALL=C

if ((EUID == 0)); then
    echo "Run the tests as a normal user: as root the helper would use the real battery." >&2
    exit 1
fi

script=$(realpath "$(dirname "$0")/../package/contents/scripts/chargelimit-helper")
sysfs=$(mktemp -d)
trap 'rm -rf "$sysfs"' EXIT
export CHARGE_LIMIT_SYSFS=$sysfs
failed=0

helper() { bash "$script" "$@"; }
value() { cat "$sysfs/$1"; }
thresholds() { echo "$(value "$1/charge_control_start_threshold") $(value "$1/charge_control_end_threshold")"; }

check() { # name expected actual
    if [[ $2 == "$3" ]]; then
        echo "ok      $1"
    else
        echo "FAILED  $1: expected '$2', got '$3'"
        failed=1
    fi
}

# supply NAME TYPE [ATTRIBUTE=VALUE...] creates a fake power supply.
supply() {
    local dir=$sysfs/$1 attribute
    mkdir -p "$dir"
    echo "$2" >"$dir/type"
    shift 2
    for attribute in "$@"; do
        echo "${attribute#*=}" >"$dir/${attribute%%=*}"
    done
}

reset() { rm -rf "${sysfs:?}"/*; }

# A ThinkPad-like laptop with a wireless mouse.
supply AC Mains online=1
supply BAT0 Battery capacity=78 status=Charging charge_control_start_threshold=0 charge_control_end_threshold=100
supply hidpp_battery_0 Battery scope=Device capacity=50 charge_control_end_threshold=100

check "status" "limit=100 capacity=78 state=Charging" "$(helper status | grep -v '^helper=' | paste -sd' ')"
helper set 80
check "set 80" "75 80" "$(thresholds BAT0)"
check "status after set 80" "limit=80" "$(helper status | grep '^limit=')"
check "the mouse is left alone" 100 "$(value hidpp_battery_0/charge_control_end_threshold)"
helper set 100
check "set 100" "95 100" "$(thresholds BAT0)"
helper set 50
check "set 50" "45 50" "$(thresholds BAT0)"
helper set 90
check "set 90" "85 90" "$(thresholds BAT0)"

for bad in 19 101 080 8 abc "" "80 90" -5; do
    check "rejects '$bad'" "The charge limit must be 20-100, not '$bad'" "$(helper set "$bad" 2>&1 || true)"
done
check "rejected values change nothing" "85 90" "$(thresholds BAT0)"
check "install needs root" "install must run as root" "$(helper install 80 2>&1 || true)"
check "usage" "Usage: chargelimit-helper status | set LIMIT | install [LIMIT]" "$(helper bogus 2>&1 || true)"

# Every battery is set, e.g. ThinkPads with two batteries.
supply BAT1 Battery capacity=40 status=Charging charge_control_start_threshold=0 charge_control_end_threshold=100
helper set 80
check "both batteries" "75 80, 75 80" "$(thresholds BAT0), $(thresholds BAT1)"

# Laptops with only a stop threshold, e.g. ASUS.
reset
supply BAT1 Battery capacity=90 status=Full charge_control_end_threshold=100
helper set 60
check "stop threshold only" 60 "$(value BAT1/charge_control_end_threshold)"
check "no start threshold is added" no "$([[ -e $sysfs/BAT1/charge_control_start_threshold ]] && echo yes || echo no)"

# Laptops that need the "Custom" charge mode, e.g. Dell.
reset
supply BAT0 Battery charge_control_start_threshold=50 charge_control_end_threshold=100 "charge_types=[Standard] Custom Long_Life"
helper set 80
check "custom charge mode" "Custom" "$(value BAT0/charge_types)"
echo "Standard [Custom] Long_Life" >"$sysfs/BAT0/charge_types"
helper set 100
check "standard charge mode at 100%" "Standard" "$(value BAT0/charge_types)"

# A rejected charge-mode change must not look like a successful limit change.
echo "[Standard] Custom Long_Life" >"$sysfs/BAT0/charge_types"
chmod 444 "$sysfs/BAT0/charge_types"
result=0
output=$(helper set 80 2>&1) || result=$?
check "charge mode write fails" 1 "$result"
check "charge mode error" "Could not set charge_types to Custom: Permission denied" "$output"
check "failed charge mode is unchanged" "[Standard] Custom Long_Life" "$(value BAT0/charge_types)"

# Write errors are reported with the reason.
reset
supply BAT0 Battery charge_control_start_threshold=0 charge_control_end_threshold=100
chmod 444 "$sysfs/BAT0/charge_control_end_threshold"
check "write error" "Could not set charge_control_end_threshold to 80: Permission denied" "$(helper set 80 2>&1 || true)"

# Desktops: no battery with a charge limit.
reset
supply AC Mains online=1
supply hidpp_battery_0 Battery scope=Device capacity=50
check "desktop status" "" "$(helper status | grep -v '^helper=' || true)"
check "desktop set" "No battery with a charge limit was found" "$(helper set 80 2>&1 || true)"

exit $failed
