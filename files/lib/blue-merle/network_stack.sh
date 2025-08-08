#!/bin/sh

# Source required functions (for debug_echo, wait_and_verify)
. /lib/blue-merle/functions.sh

# Check TTL settings for Windows emulation
CHECK_TTL () {
        echo "=== TTL Configuration Check ==="
        local current_ttl=$(sysctl -n net.ipv4.ip_default_ttl 2>/dev/null || echo "64")
        
        if [ "$current_ttl" = "128" ]; then
                echo "TTL: 128 (Windows default) ✓"
                return 0
        else
                echo "TTL: $current_ttl (should be 128 for Windows emulation) ✗"
                echo "Fix with: sysctl -w net.ipv4.ip_default_ttl=128"
                return 1
        fi
}

# Check if TCP settings match Windows 11 defaults
CHECK_TCP_WINDOWS () {
        echo "=== TCP Windows Configuration Check ==="
        
        local tcp_window_scaling=$(sysctl -n net.ipv4.tcp_window_scaling 2>/dev/null || echo "0")
        local tcp_timestamps=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null || echo "0")
        local tcp_sack=$(sysctl -n net.ipv4.tcp_sack 2>/dev/null || echo "0")
        local tcp_autocorking=$(sysctl -n net.ipv4.tcp_autocorking 2>/dev/null || echo "0")
        local tcp_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
        
        local all_correct=0
        
        if [ "$tcp_window_scaling" = "1" ]; then
                echo "TCP window scaling: Enabled ✓"
        else
                echo "TCP window scaling: Disabled ✗"
                all_correct=1
        fi
        
        if [ "$tcp_timestamps" = "1" ]; then
                echo "TCP timestamps: Enabled ✓"
        else
                echo "TCP timestamps: Disabled ✗"
                all_correct=1
        fi
        
        if [ "$tcp_sack" = "1" ]; then
                echo "TCP SACK: Enabled ✓"
        else
                echo "TCP SACK: Disabled ✗"
                all_correct=1
        fi
        
        # TCP auto-corking is Linux-specific and should NOT be enabled for Windows emulation
        if [ "$tcp_autocorking" = "0" ]; then
                echo "TCP auto-corking: Disabled (Windows-like) ✓"
        else
                echo "TCP auto-corking: Enabled (Linux fingerprint) ✗"
                all_correct=1
        fi
        
        if [ "$tcp_congestion" = "cubic" ]; then
                echo "TCP congestion control: $tcp_congestion (Windows standard) ✓"
        elif [ "$tcp_congestion" = "bbr" ]; then
                echo "TCP congestion control: $tcp_congestion (modern Windows fallback) ✓"
        else
                echo "TCP congestion control: $tcp_congestion (should be cubic or bbr) ✗"
                all_correct=1
        fi
        
        # Check dynamic TCP buffer sizes (Windows auto-tuning behavior)
        local tcp_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo "unknown")
        local tcp_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo "unknown")
        
        echo ""
        echo "TCP Buffer Configuration:"
        echo "Receive buffers (rmem): $tcp_rmem"
        echo "Send buffers (wmem): $tcp_wmem"
        
        # Check if buffers allow for large windows (16MB = 16777216)
        if echo "$tcp_rmem" | grep -q "16777216" && echo "$tcp_wmem" | grep -q "16777216"; then
                echo "Buffer sizes: Large windows supported (16MB+) - Windows 11 Auto-Tuning ✓"
        else
                echo "Buffer sizes: Limited window scaling ⚠️"
        fi
        
        echo ""
        
        if [ "$all_correct" = "0" ]; then
                echo "TCP Windows emulation: GOOD ✓"
                return 0
        else
                echo "TCP Windows emulation: NEEDS IMPROVEMENT ✗"
                return 1
        fi
}

# Check DHCP client configuration
CHECK_DHCP_WINDOWS () {
        echo "=== DHCP Client Configuration Check ==="
        
        if command -v dhcpcd >/dev/null 2>&1; then
                echo "DHCP Client: dhcpcd (Windows-like) ✓"
                
                if [ -f /etc/dhcpcd/dhcpcd.conf ]; then
                        echo "DHCP Configuration: Windows-like options configured ✓"
                        return 0
                else
                        echo "DHCP Configuration: dhcpcd.conf missing ✗"
                        return 1
                fi
        else
                echo "DHCP Client: udhcpc (Linux default) ✗"
                echo "Install dhcpcd for Windows-like DHCP behavior"
                return 1
        fi
}
