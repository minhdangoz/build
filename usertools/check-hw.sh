#!/bin/bash
# Hardware check: wifi, bluetooth, ethernet, hdmi
# Read-only diagnostic. Does not modify system state.

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

echo "== WiFi =="
if command -v nmcli &>/dev/null; then
    wifi_dev=$(nmcli -t -f DEVICE,TYPE device | grep ':wifi$' | cut -d: -f1)
    if [ -z "$wifi_dev" ]; then
        fail "No wifi device found"
    else
        state=$(nmcli -t -f DEVICE,STATE device | grep "^$wifi_dev:" | cut -d: -f2)
        if [ "$state" == "connected" ]; then
            ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
            pass "Device $wifi_dev connected to '$ssid'"
        else
            warn "Device $wifi_dev present but state=$state"
        fi
    fi
else
    fail "nmcli not found (install network-manager)"
fi
rfkill list wifi 2>/dev/null | grep -q "yes" && warn "WiFi soft/hard blocked via rfkill"

if command -v nmcli &>/dev/null; then
    nmcli device wifi rescan 2>/dev/null
    sleep 3
    net_count=$(nmcli -t -f SSID device wifi list 2>/dev/null | grep -v '^--$' | grep -v '^$' | sort -u | wc -l)
    if [ "$net_count" -gt 0 ]; then
        pass "Scan found $net_count network(s)"
    else
        warn "Scan found no networks"
    fi
fi

echo
echo "== Bluetooth =="
if command -v bluetoothctl &>/dev/null; then
    if systemctl is-active --quiet bluetooth; then
        pass "bluetooth.service is active"
    else
        fail "bluetooth.service is not active"
    fi
    powered=$(bluetoothctl show | grep -i "Powered:" | awk '{print $2}')
    if [ "$powered" == "yes" ]; then
        pass "Adapter powered on"
    else
        fail "Adapter not powered on"
    fi
else
    fail "bluetoothctl not found (install bluez)"
fi
rfkill list bluetooth 2>/dev/null | grep -q "yes" && warn "Bluetooth soft/hard blocked via rfkill"

if command -v bluetoothctl &>/dev/null && [ "$powered" == "yes" ]; then
    timeout 6 bluetoothctl scan on &>/dev/null
    bluetoothctl scan off &>/dev/null
    bt_count=$(bluetoothctl devices | wc -l)
    if [ "$bt_count" -gt 0 ]; then
        pass "Scan found $bt_count device(s)"
    else
        warn "Scan found no devices (may need longer scan or none nearby)"
    fi
fi

echo
echo "== Ethernet =="
eth_devs=$(ls /sys/class/net | grep -E '^(eth|en[a-z0-9]+)' 2>/dev/null)
if [ -z "$eth_devs" ]; then
    fail "No ethernet device found"
else
    for dev in $eth_devs; do
        carrier=$(cat /sys/class/net/"$dev"/carrier 2>/dev/null)
        state=$(cat /sys/class/net/"$dev"/operstate 2>/dev/null)
        if [ "$carrier" == "1" ]; then
            speed="unknown"
            if command -v ethtool &>/dev/null; then
                speed=$(ethtool "$dev" 2>/dev/null | grep -oP 'Speed: \K.*')
            fi
            pass "$dev link up (state=$state, speed=$speed)"
        else
            warn "$dev present but no carrier/link (cable unplugged? state=$state)"
        fi
    done
fi

echo
echo "== HDMI =="
if [ -d /sys/class/drm ]; then
    hdmi_connectors=$(ls /sys/class/drm | grep -i hdmi)
    if [ -z "$hdmi_connectors" ]; then
        warn "No HDMI connectors detected by DRM"
    else
        for conn in $hdmi_connectors; do
            status=$(cat /sys/class/drm/"$conn"/status 2>/dev/null)
            if [ "$status" == "connected" ]; then
                pass "$conn connected"
            else
                warn "$conn status=$status (no display plugged in?)"
            fi
        done
    fi
else
    fail "/sys/class/drm not found (no GPU driver loaded?)"
fi