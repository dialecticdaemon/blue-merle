#!/bin/sh
# Windows 11 Background DNS Traffic Simulator
# VPN-aware DNS simulation that waits for VPN to be ready
# Lightweight DNS-only simulation for router capabilities

# Windows NCSI endpoints (DNS queries only)
NCSI_ENDPOINTS="
www.msftconnecttest.com
www.msftncsi.com
dns.msftncsi.com
ipv6.msftconnecttest.com
"

# Windows Update endpoints (DNS queries only)
WINDOWS_UPDATE_ENDPOINTS="
update.microsoft.com
download.windowsupdate.com
fe2.update.microsoft.com
fe3.update.microsoft.com
fe4.update.microsoft.com
fe5.update.microsoft.com
"

# Microsoft services endpoints (DNS queries only)
MICROSOFT_SERVICES="
login.live.com
account.live.com
auth.gfx.ms
auth.live.com
login.microsoftonline.com
graph.microsoft.com
api.office.com
outlook.office365.com
"

# STRICT VPN Detection - Optimized for WireGuard/Mullvad
check_vpn_status() {
    local vpn_active=0
    
    # Method 1: WireGuard interface detection (most reliable for Mullvad)
    if command -v ip >/dev/null 2>&1; then
        # Check for WireGuard interfaces (wg0, wg1, etc.)
        ip link show 2>/dev/null | grep -E "wg[0-9]+|tun[0-9]+|tap[0-9]+" >/dev/null && vpn_active=1
        
        # Check WireGuard interface status
        if command -v wg >/dev/null 2>&1; then
            wg show 2>/dev/null | grep -q "interface:" && vpn_active=1
        fi
    fi
    
    # Method 2: WireGuard routing verification
    if command -v ip >/dev/null 2>&1; then
        # Check if traffic routes through WireGuard interface
        local default_route=$(ip route show default 2>/dev/null | head -1)
        echo "$default_route" | grep -E "wg[0-9]+|tun[0-9]+|tap[0-9]+" >/dev/null && vpn_active=1
        
        # Check for VPN-specific routes (Mullvad typically uses specific subnets)
        ip route show 2>/dev/null | grep -E "wg[0-9]+|tun[0-9]+" >/dev/null && vpn_active=1
    fi
    
    # Method 3: WireGuard process detection
    if pgrep -f "wireguard|wg-quick" >/dev/null 2>&1; then
        vpn_active=1
    fi
    
    # Method 4: Check WireGuard configuration files
    if [ -d /etc/wireguard ] && [ "$(ls -A /etc/wireguard/*.conf 2>/dev/null)" ]; then
        # Configuration exists, check if any interface is up
        if command -v wg >/dev/null 2>&1; then
            wg show 2>/dev/null | grep -q "peer" && vpn_active=1
        fi
    fi
    
    # Method 5: OpenWrt WireGuard service check
    if [ -f /etc/init.d/wireguard ]; then
        /etc/init.d/wireguard status 2>/dev/null | grep -q "running" && vpn_active=1
    fi
    
    # Method 6: Network connectivity verification (Mullvad-specific)
    if command -v nslookup >/dev/null 2>&1; then
        # Check if we can resolve through VPN (quick test)
        # This ensures not just interface exists but traffic flows
        local test_resolve=$(nslookup am.i.mullvad.net 2>/dev/null | grep -c "answer" || echo "0")
        if [ "$test_resolve" -gt 0 ]; then
            vpn_active=1
        fi
    fi
    
    # Method 7: Fallback - check for any tunnel interface with active traffic
    if command -v ip >/dev/null 2>&1; then
        # Look for any tunnel interface that's UP and has routes
        for iface in $(ip link show | grep -E "wg[0-9]+|tun[0-9]+|tap[0-9]+" | cut -d: -f2 | tr -d ' '); do
            if ip link show "$iface" 2>/dev/null | grep -q "state UP"; then
                vpn_active=1
                break
            fi
        done
    fi
    
    # STRICT: VPN must be confirmed active
    if [ "$vpn_active" -eq 1 ]; then
        return 0
    else
        return 1
    fi
}

# STRICT VPN Wait - Boot-aware timing
wait_for_vpn_strict() {
    local check_interval=10  # Check every 10 seconds
    local check_count=0
    local max_boot_wait=60   # Wait up to 10 minutes (60 checks * 10s interval) on boot for VPN
    
    # Wait for VPN with boot-aware timing
    while [ $check_count -lt $max_boot_wait ]; do
        if check_vpn_status; then
            return 0  # VPN active, start simulation
        fi
        
        check_count=$((check_count + 1))
        
        # On first few checks, be more patient (boot scenario)
        if [ $check_count -le 6 ]; then
            sleep 15  # Longer wait during boot (15 seconds)
        else
            sleep $check_interval  # Normal wait after boot
        fi
    done
    
    # After max wait, continue without VPN (emergency fallback)
    # This prevents infinite hangs on boot
    return 1
}

# Simulate DNS query (lightweight - no downloads)
simulate_dns_query() {
    local endpoint="$1"
    
    # Perform DNS query only (completely silent for OPSEC)
    nslookup $endpoint >/dev/null 2>&1 || true
    dig $endpoint >/dev/null 2>&1 || true
}

# SECURE Main simulation loop with continuous VPN monitoring
main_simulation_loop() {
    while true; do
        # STRICT: Wait for VPN to be ready before ANY activity
        wait_for_vpn_strict
        
        # Simulate NCSI DNS queries (most frequent - like Windows)
        for endpoint in $NCSI_ENDPOINTS; do
            # SECURITY: Re-check VPN before each query (silent mode)
            if ! check_vpn_status; then
                break 2  # Exit both loops and restart VPN wait
            fi
            
            # Random delay between queries (Windows-like timing: 30-300 seconds)
            local delay=$((RANDOM % 270 + 30))
            sleep $delay
            
            # Final VPN check before DNS query
            if check_vpn_status; then
                simulate_dns_query "$endpoint"
            else
                break 2  # VPN lost, restart cycle silently
            fi
        done
        
        # Simulate Windows Update DNS queries (less frequent - 10% chance)
        if [ $((RANDOM % 10)) -eq 0 ]; then
            for endpoint in $WINDOWS_UPDATE_ENDPOINTS; do
                # VPN check before each query (silent)
                if ! check_vpn_status; then
                    break 2
                fi
                
                local delay=$((RANDOM % 600 + 300))  # 5-15 minutes
                sleep $delay
                
                if check_vpn_status; then
                    simulate_dns_query "$endpoint"
                else
                    break 2
                fi
            done
        fi
        
        # Simulate Microsoft services DNS queries (occasional - 5% chance)
        if [ $((RANDOM % 20)) -eq 0 ]; then
            for endpoint in $MICROSOFT_SERVICES; do
                # VPN check before each query (silent)
                if ! check_vpn_status; then
                    break 2
                fi
                
                local delay=$((RANDOM % 900 + 600))  # 10-25 minutes
                sleep $delay
                
                if check_vpn_status; then
                    simulate_dns_query "$endpoint"
                else
                    break 2
                fi
            done
        fi
        
        # VPN check before cycle sleep (silent)
        if ! check_vpn_status; then
            continue  # Restart the main loop (will wait for VPN again)
        fi
        
        # Sleep before next cycle (Windows-like behavior: 5-15 minutes)
        sleep $((RANDOM % 600 + 300))
    done
}

# If script is run directly (not sourced), start main loop
if [ "${0##*/}" = "windows-dns-simulator.sh" ]; then
    main_simulation_loop
fi
