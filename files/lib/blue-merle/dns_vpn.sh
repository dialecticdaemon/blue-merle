#!/bin/sh

# Source the DNS simulator functions
. /lib/blue-merle/windows-dns-simulator.sh

# Check Windows background DNS traffic simulation with VPN security
CHECK_DNS_SIMULATION () {
        echo "=== Windows Background DNS Traffic Simulation Check ==="
        
        # Check if DNS simulator script exists
        if [ -f /lib/blue-merle/windows-dns-simulator.sh ]; then
                echo "DNS simulator script: Present ✓"
        else
                echo "DNS simulator script: Missing ✗"
                return 1
        fi
        
        # Check VPN status FIRST (security critical)
        echo ""
        echo "=== VPN Security Check ==="
        
        # Check for WireGuard interfaces (Mullvad VPN)
        local vpn_interface_found=0
        if command -v ip >/dev/null 2>&1; then
                local wg_interfaces=$(ip link show 2>/dev/null | grep -E -c "wg[0-9]+|tun[0-9]+|tap[0-9]+" || echo "0")
                if [ "$wg_interfaces" -gt 0 ]; then
                        echo "WireGuard interfaces: $wg_interfaces found ✓"
                        vpn_interface_found=1
                        
                        # Show interface details
                        local wg_interface=$(ip link show 2>/dev/null | grep -E "wg[0-9]+|tun[0-9]+" | head -1 | cut -d: -f2 | tr -d ' ')
                        if [ -n "$wg_interface" ]; then
                                echo "Active interface: $wg_interface"
                        fi
                else
                        echo "WireGuard interfaces: None found ✗"
                fi
        fi
        
        # Check WireGuard tool availability and status
        if command -v wg >/dev/null 2>&1; then
                local wg_peers=$(wg show 2>/dev/null | grep -c "peer:" || echo "0")
                if [ "$wg_peers" -gt 0 ]; then
                        echo "WireGuard peers: $wg_peers connected ✓"
                        vpn_interface_found=1
                else
                        echo "WireGuard peers: None connected ✗"
                fi
        else
                echo "WireGuard tool: Not available (checking fallback methods)"
        fi
        
        # Check VPN routing (WireGuard specific)
        local vpn_routing=0
        if command -v ip >/dev/null 2>&1; then
                ip route show 2>/dev/null | grep -E "wg[0-9]+|tun[0-9]+" >/dev/null && vpn_routing=1
                if [ "$vpn_routing" -eq 1 ]; then
                        echo "VPN routing: Active ✓"
                        
                        # Show default route info
                        local default_route=$(ip route show default 2>/dev/null | head -1)
                        if echo "$default_route" | grep -E "wg[0-9]+|tun[0-9]+" >/dev/null; then
                                echo "Default route: Through VPN ✓"
                        else
                                echo "Default route: May not use VPN ⚠️"
                        fi
                else
                        echo "VPN routing: Not found ✗"
                fi
        fi
        
        # Check WireGuard processes
        local vpn_processes=$(pgrep -f "wireguard|wg-quick" 2>/dev/null | wc -l)
        if [ "$vpn_processes" -gt 0 ]; then
                echo "WireGuard processes: $vpn_processes running ✓"
        else
                echo "WireGuard processes: None running ✗"
        fi
        
        # Mullvad connectivity test
        if command -v nslookup >/dev/null 2>&1; then
                local mullvad_test=$(nslookup am.i.mullvad.net 2>/dev/null | grep -c "answer" || echo "0")
                if [ "$mullvad_test" -gt 0 ]; then
                        echo "Mullvad connectivity: Reachable ✓"
                else
                        echo "Mullvad connectivity: Not reachable ⚠️"
                fi
        fi
        
        # Overall VPN status
        if [ "$vpn_interface_found" -eq 1 ] && [ "$vpn_routing" -eq 1 ] && [ "$vpn_processes" -gt 0 ]; then
                echo "VPN Status: SECURE ✓"
        else
                echo "VPN Status: INSECURE - DNS simulation should not run ✗"
                echo "WARNING: DNS queries without VPN protection leak location data!"
        fi
        
        echo ""
        echo "=== DNS Simulation Status ==="
        
        # Check if DNS simulator is running
        local dns_pid=$(pgrep -f "windows-dns-simulator" 2>/dev/null || echo "")
        if [ -n "$dns_pid" ]; then
                echo "DNS simulation: Running (PID: $dns_pid) ✓"
                
                # Security validation
                if [ "$vpn_interface_found" -eq 1 ] && [ "$vpn_routing" -eq 1 ]; then
                        echo "Security status: SECURE - VPN protects DNS queries ✓"
                        return 0
                else
                        echo "Security status: INSECURE - DNS queries leak data ✗"
                        return 1
                fi
        else
                echo "DNS simulation: Not running ✗"
                return 1
        fi
}

# Test DNS simulator functionality during blue-merle runs
TEST_DNS_SIMULATOR () {
        echo "=== DNS Simulator Test ==="
        
        # Check if script exists
        if [ -f /lib/blue-merle/windows-dns-simulator.sh ]; then
                echo "DNS simulator script: Present ✓"
        else
                echo "DNS simulator script: Missing ✗"
                return 1
        fi
        
        # Test VPN detection function
        echo ""
        echo "Testing VPN detection..."
        if check_vpn_status; then
                echo "VPN Status: Active ✓"
                echo "DNS simulation: Safe to run ✓"
        else
                echo "VPN Status: Inactive ✗"
                echo "DNS simulation: Would wait for VPN ⚠️"
        fi
        
        # Test DNS query function
        echo ""
        echo "Testing DNS query function..."
        local test_endpoint="www.msftconnecttest.com"
        echo "Testing query to: $test_endpoint"
        
        if command -v nslookup >/dev/null 2>&1; then
                if nslookup $test_endpoint >/dev/null 2>&1; then
                        echo "DNS query test: SUCCESS ✓"
                else
                        echo "DNS query test: FAILED ✗"
                fi
        else
                echo "DNS tools: nslookup not available ⚠️"
        fi
        
        # Check if simulator is running
        echo ""
        echo "Checking simulator process..."
        local dns_pid=$(pgrep -f "windows-dns-simulator" 2>/dev/null || echo "")
        if [ -n "$dns_pid" ]; then
                echo "DNS simulator: Running (PID: $dns_pid) ✓"
        else
                echo "DNS simulator: Not running ✗"
        fi
        
        # Test simulation function components
        echo ""
        echo "Testing simulation components..."
        
        # Test endpoint lists
        local ncsi_count=$(echo "$NCSI_ENDPOINTS" | grep -c "msft" || echo "0")
        local update_count=$(echo "$WINDOWS_UPDATE_ENDPOINTS" | grep -c "update" || echo "0")
        local services_count=$(echo "$MICROSOFT_SERVICES" | grep -c "live\|office\|graph" || echo "0")
        
        echo "NCSI endpoints: $ncsi_count configured ✓"
        echo "Windows Update endpoints: $update_count configured ✓"
        echo "Microsoft services: $services_count configured ✓"
        
        echo ""
        echo "DNS Simulator Test Complete"
        return 0
}
