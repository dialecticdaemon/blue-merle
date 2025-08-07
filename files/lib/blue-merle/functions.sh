#!/usr/bin/env ash

# This script provides helper functions for blue-merle


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

# Check if TTL is set to Windows default (128)
CHECK_TTL () {
        local current_ttl=$(sysctl -n net.ipv4.ip_default_ttl 2>/dev/null || echo "0")
        if [[ "$current_ttl" -eq 128 ]]; then
                echo "TTL is correctly set to Windows default (128)"
                return 0
        else
                echo "TTL is set to $current_ttl (should be 128 for Windows emulation)"
                return 1
        fi
}

# Check if TCP settings match Windows defaults
CHECK_TCP_WINDOWS () {
        local tcp_window_scaling=$(sysctl -n net.ipv4.tcp_window_scaling 2>/dev/null || echo "0")
        local tcp_timestamps=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null || echo "0")
        local tcp_sack=$(sysctl -n net.ipv4.tcp_sack 2>/dev/null || echo "0")
        local rmem_default=$(sysctl -n net.core.rmem_default 2>/dev/null || echo "0")
        local wmem_default=$(sysctl -n net.core.wmem_default 2>/dev/null || echo "0")
        
        local all_correct=0
        
        if [[ "$tcp_window_scaling" -eq 1 ]]; then
                echo "TCP window scaling: Enabled ✓"
        else
                echo "TCP window scaling: Disabled ✗"
                all_correct=1
        fi
        
        if [[ "$tcp_timestamps" -eq 1 ]]; then
                echo "TCP timestamps: Enabled ✓"
        else
                echo "TCP timestamps: Disabled ✗"
                all_correct=1
        fi
        
        if [[ "$tcp_sack" -eq 1 ]]; then
                echo "TCP SACK: Enabled ✓"
        else
                echo "TCP SACK: Disabled ✗"
                all_correct=1
        fi
        
        if [[ "$rmem_default" -eq 65536 ]]; then
                echo "Receive buffer default: 65536 ✓"
        else
                echo "Receive buffer default: $rmem_default (should be 65536) ✗"
                all_correct=1
        fi
        
        if [[ "$wmem_default" -eq 65536 ]]; then
                echo "Send buffer default: 65536 ✓"
        else
                echo "Send buffer default: $wmem_default (should be 65536) ✗"
                all_correct=1
        fi
        
        if [[ "$all_correct" -eq 0 ]]; then
                echo "All TCP settings match Windows defaults ✓"
                return 0
        else
                echo "Some TCP settings need adjustment ✗"
                return 1
        fi
}

# Check if MTU settings are optimized for LTE
CHECK_MTU_LTE () {
        local wan_mtu=$(uci -q get network.wan.mtu 2>/dev/null || echo "0")
        local tcp_mtu_probing=$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null || echo "0")
        local tcp_mtu_probe_floor=$(sysctl -n net.ipv4.tcp_mtu_probe_floor 2>/dev/null || echo "0")
        
        local all_correct=0
        
        if [[ "$wan_mtu" -eq 1428 ]]; then
                echo "WAN MTU: 1428 (LTE-optimized) ✓"
        else
                echo "WAN MTU: $wan_mtu (should be 1428 for LTE) ✗"
                all_correct=1
        fi
        
        if [[ "$tcp_mtu_probing" -eq 1 ]]; then
                echo "TCP MTU probing: Enabled ✓"
        else
                echo "TCP MTU probing: Disabled ✗"
                all_correct=1
        fi
        
        if [[ "$tcp_mtu_probe_floor" -eq 1388 ]]; then
                echo "TCP MTU probe floor: 1388 ✓"
        else
                echo "TCP MTU probe floor: $tcp_mtu_probe_floor (should be 1388) ✗"
                all_correct=1
        fi
        
        if [[ "$all_correct" -eq 0 ]]; then
                echo "All MTU settings optimized for LTE ✓"
                return 0
        else
                echo "Some MTU settings need adjustment ✗"
                return 1
        fi
}
