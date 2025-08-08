#!/usr/bin/env ash

# This script provides helper functions for blue-merle

# Global variables for Windows emulation features
export DEVICE_IMEI=""
export DEBUG_MODE=0

# Debug output function with timing (for Windows emulation features)
debug_echo() {
        if [ "$DEBUG_MODE" = "1" ]; then
                echo "[$(date '+%H:%M:%S')] $1"
        fi
}

# Adaptive wait with verification - wait until operation is ACTUALLY complete
wait_and_verify() {
    local operation="$1"
    local verify_command="$2"
    local expected_result="$3"
    local max_timeout="${4:-30}"  # Default 30s max timeout
    local check_interval="${5:-1}"  # Default 1s check interval
    
    local start_time=$(date +%s)
    local elapsed=0
    
    debug_echo "⏱️  Starting: $operation (verify until complete, max ${max_timeout}s)"
    
    while [ $elapsed -lt $max_timeout ]; do
        # Check if operation is complete
        local current_result=$(eval "$verify_command" 2>/dev/null || echo "")
        if [ "$current_result" = "$expected_result" ]; then
            local end_time=$(date +%s)
            local total_time=$((end_time - start_time))
            debug_echo "⏱️  ✓ VERIFIED: $operation completed in ${total_time}s"
            return 0
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    # Timeout reached - operation failed or taking too long
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    debug_echo "⏱️  ✗ TIMEOUT: $operation failed verification after ${total_time}s (max: ${max_timeout}s)"
    debug_echo "    Expected: '$expected_result', Got: '$(eval "$verify_command" 2>/dev/null || echo "error")'"
    return 1
}

# Simple wait with verification (no command needed, just wait)
wait_for_settle() {
    local operation="$1"
    local wait_time="$2"
    local start_time=$(date +%s)
    
    debug_echo "⏱️  Settling: $operation (${wait_time}s)"
    sleep $wait_time
    
    local end_time=$(date +%s)
    local actual_time=$((end_time - start_time))
    debug_echo "⏱️  Settled: $operation took ${actual_time}s"
}

# ORIGINAL CORE BLUE-MERLE FUNCTIONS (DO NOT MODIFY)

UNICAST_MAC_GEN () {
    loc_mac_numgen=`python3 -c "import random; print(f'{random.randint(0,2**48) & 0b111111101111111111111111111111111111111111111111:0x}'.zfill(12))"`
    loc_mac_formatted=$(echo "$loc_mac_numgen" | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4:\5:\6/')
    echo "$loc_mac_formatted"
}

# randomize BSSID
RESET_BSSIDS () {
    uci set wireless.@wifi-iface[1].macaddr=`UNICAST_MAC_GEN`
    uci set wireless.@wifi-iface[0].macaddr=`UNICAST_MAC_GEN`
    uci commit wireless
    # you need to reset wifi for changes to apply, i.e. executing "wifi"
}

RANDOMIZE_MACADDR () {
    # This changes the MAC address clients see when connecting to the WiFi spawned by the device.
    # You can check with "arp -a" that your endpoint, e.g. your laptop, sees a different MAC after a reboot of the Mudi.
    uci set network.@device[1].macaddr=`UNICAST_MAC_GEN`
    # Here we change the MAC address the upstream wifi sees
    uci set glconfig.general.macclone_addr=`UNICAST_MAC_GEN`
    uci commit network
    # You need to restart the network, i.e. /etc/init.d/network restart
}

READ_ICCID() {
    gl_modem AT AT+CCID
}

READ_IMEI () {
	local answer=1
	while [[ "$answer" -eq 1 ]]; do
	        local imei=$(gl_modem AT AT+GSN | grep -w -E "[0-9]{14,15}")
	        if [[ $? -eq 1 ]]; then
                	echo -n "Failed to read IMEI. Try again? (Y/n): "
	                read answer
	                case $answer in
	                        n*) answer=0;;
	                        N*) answer=0;;
	                        *) answer=1;;
	                esac
	                if [[ $answer -eq 0 ]]; then
	                        exit 1
	                fi
	        else
	                answer=0
	        fi
	done
	echo $imei
}

READ_IMSI () {
	local answer=1
	while [[ "$answer" -eq 1 ]]; do
	        local imsi=$(gl_modem AT AT+CIMI | grep -w -E "[0-9]{6,15}")
	        if [[ $? -eq 1 ]]; then
                	echo -n "Failed to read IMSI. Try again? (Y/n): "
	                read answer
	                case $answer in
	                        n*) answer=0;;
	                        N*) answer=0;;
	                        *) answer=1;;
	                esac
	                if [[ $answer -eq 0 ]]; then
	                        exit 1
	                fi
	        else
	                answer=0
	        fi
	done
	echo $imsi
}

GENERATE_IMEI() {
    local seed=$(head -100 /dev/urandom | tr -dc "0123456789" | head -c10)
    local imei=$(lua /lib/blue-merle/luhn.lua $seed)
    echo -n $imei
}

SET_IMEI() {
    local imei="$1"

    if [[ ${#imei} -eq 14 ]]; then
        gl_modem AT AT+EGMR=1,7,${imei}
    else
        echo "IMEI is ${#imei} not 14 characters long"
    fi
}

CHECK_ABORT () {
        sim_change_switch=`cat /tmp/sim_change_switch`
        if [[ "$sim_change_switch" = "off" ]]; then
                echo '{ "msg": "SIM change      aborted." }' > /dev/ttyS0
                sleep 1
                exit 1
        fi
}