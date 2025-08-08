#!/bin/sh

# Source required functions (for debug_echo)
. /lib/blue-merle/functions.sh

# Check persistence of network settings
CHECK_PERSISTENCE () {
        echo "=== Network Settings Persistence Check ==="
        
        # Check sysctl settings
        local ttl_persist=$(cat /etc/sysctl.conf 2>/dev/null | grep -c "net.ipv4.ip_default_ttl=128" || echo "0")
        local tcp_persist=$(cat /etc/sysctl.conf 2>/dev/null | grep -c "net.ipv4.tcp_window_scaling=1" || echo "0")
        
        if [ "$ttl_persist" -eq 0 ]; then
                echo "TTL setting: Not persistent ⚠️"
                echo "Add 'net.ipv4.ip_default_ttl=128' to /etc/sysctl.conf for persistence"
        else
                echo "TTL setting: Persistent ✓"
        fi
        
        if [ "$tcp_persist" -eq 0 ]; then
                echo "TCP settings: Not persistent ⚠️"
                echo "Add TCP settings to /etc/sysctl.conf for persistence"
        else
                echo "TCP settings: Persistent ✓"
        fi
        
        # Check MTU persistence
        if uci -q get network.wan.mtu >/dev/null; then
                echo "WAN MTU: Persistent (UCI) ✓"
        else
                echo "WAN MTU: Not configured in UCI ⚠️"
        fi
        
        # Check DHCP persistence
        if command -v dhcpcd >/dev/null 2>&1; then
                if [ -f /etc/dhcpcd/dhcpcd.conf ]; then
                        echo "DHCP configuration: Persistent (configured during installation) ✓"
                        
                        # Check if configuration contains Windows-like options
                        if grep -q "rapid_commit" /etc/dhcpcd/dhcpcd.conf && \
                           grep -q "option domain_name_servers" /etc/dhcpcd/dhcpcd.conf; then
                                echo "DHCP options: Windows-like configuration present ✓"
                        else
                                echo "DHCP options: Missing Windows-like configuration ⚠️"
                        fi
                else
                        echo "DHCP configuration: Missing configuration file ⚠️"
                fi
        else
                echo "DHCP client: dhcpcd not installed ⚠️"
        fi
        
        # Check firewall rules persistence
        if uci -q get firewall.block_openwrt_traffic >/dev/null && \
           uci -q get firewall.block_openwrt_ntp >/dev/null && \
           uci -q get firewall.block_opkg_repos >/dev/null; then
                echo "Firewall rules: Persistent (UCI) ✓"
        else
                echo "Firewall rules: Not all rules present ⚠️"
        fi
        
        echo ""
        echo "Note: DHCP and firewall configurations are set during package installation"
        echo "      Network settings (TTL, TCP) require sysctl.conf for persistence"
        echo "      UCI-based settings (MTU, firewall) are automatically persistent"
        
        # Return success if most settings are persistent
        local issues=0
        [ "$ttl_persist" -eq 0 ] && issues=$((issues + 1))
        [ ! -f /etc/dhcpcd/dhcpcd.conf ] && issues=$((issues + 1))
        
        if [ "$issues" -le 1 ]; then
                return 0
        else
                return 1
        fi
}
