include $(TOPDIR)/rules.mk

PKG_NAME:=blue-merle
PKG_VERSION:=2.0.4
PKG_RELEASE:=$(AUTORELEASE)

PKG_MAINTAINER:=Matthias <matthias@srlabs.de>
PKG_LICENSE:=BSD-3-Clause

include $(INCLUDE_DIR)/package.mk

define Package/blue-merle
	SECTION:=utils
	CATEGORY:=Utilities
	EXTRA_DEPENDS:=luci-base, gl-sdk4-mcu, coreutils-shred, python3-pyserial
	TITLE:=Anonymity Enhancements for GL-E750 Mudi
endef

define Package/blue-merle/description
	The blue-merle package enhances anonymity and reduces forensic traceability of the GL-E750 Mudi 4G mobile wi-fi router
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/blue-merle/install
	$(CP) ./files/* $(1)/
	$(INSTALL_BIN) ./files/etc/init.d/* $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/gl-switch.d/* $(1)/etc/gl-switch.d/
	$(INSTALL_BIN) ./files/usr/bin/* $(1)/usr/bin/
	$(INSTALL_BIN) ./files/usr/libexec/blue-merle $(1)/usr/libexec/blue-merle
	$(INSTALL_BIN) ./files/lib/blue-merle/imei_generate.py  $(1)/lib/blue-merle/imei_generate.py
	$(INSTALL_DATA) ./files/lib/blue-merle/*.sh $(1)/lib/blue-merle/
endef

define Package/blue-merle/preinst
	#!/bin/sh
	[ -n "$${IPKG_INSTROOT}" ] && exit 0	# if run within buildroot exit
	
	ABORT_GLVERSION () {
		echo
		if [ -f "/tmp/sysinfo/model" ] && [ -f "/etc/glversion" ]; then
			echo "You have a `cat /tmp/sysinfo/model`, running firmware version `cat /etc/glversion`."
		fi
		echo "blue-merle has only been tested with GL-E750 Mudi Versions up to 4.3.19"
		echo "The device or firmware version you are using have not been verified to work with blue-merle."
		echo -n "Would you like to continue on your own risk? (y/N): "
		read answer
		case $$answer in
				y*) answer=0;;
				y*) answer=0;;
				*) answer=1;;
		esac
		if [[ "$$answer" -eq 0 ]]; then
			exit 0
		else
			exit 1
		fi
	}

	if grep -q "GL.iNet GL-E750" /proc/cpuinfo; then
	    GL_VERSION=$$(cat /etc/glversion)
	    case $$GL_VERSION in
		4.3.19)
		    echo Version $$GL_VERSION is supported
		    exit 0
		    ;;
		4.*)
	            echo Version $$GL_VERSION is *probably* supported
	            ABORT_GLVERSION
	            ;;
	        *)
	            echo Unknown version $$GL_VERSION
	            ABORT_GLVERSION
	            ;;
        esac
        CHECK_MCUVERSION
	else
		ABORT_GLVERSION
	fi

    # Our volatile-mac service gets started during the installation
    # but it modifies the client database held by the gl_clients process.
    # So we stop that process now, have the database put onto volatile storage
    # and start the service after installation
    /etc/init.d/gl_clients stop
endef

define Package/blue-merle/postinst
	#!/bin/sh
	
	# Install required packages during blue-merle installation (ONE TIME ONLY)
	echo "Installing required packages for Windows emulation..."
	
	# Update package lists and install dhcpcd (Windows-like DHCP client with Option 55 support)
	echo "Updating package lists..."
	opkg update
	sleep 2  # Wait for package list update
	
	echo "Installing dhcpcd..."
	if ! opkg install dhcpcd; then
		echo "Warning: Failed to install dhcpcd - will use default DHCP client"
	else
		echo "✓ dhcpcd installed successfully"
		sleep 1  # Wait for installation to complete
		
		# Configure dhcpcd with Windows-like behavior (ONE TIME ONLY)
		echo "Configuring DHCP client for Windows emulation..."
		mkdir -p /etc/dhcpcd 2>/dev/null || true
		
		cat > /etc/dhcpcd/dhcpcd.conf << 'EOF'
# Windows 11 DHCP Configuration
# Rapid commit for faster lease acquisition
rapid_commit

# Windows-like hostname behavior
hostname

# Windows-like DNS behavior
domain_name_servers
domain_name

# Windows-like lease time behavior
persistent

# Windows-like option requests
option rapid_commit
option domain_name_servers
option domain_name
option routers
option subnet_mask
option broadcast_address
option static_routes
option classless_static_routes
option interface_mtu
option ntp_servers
option time_offset
option time_servers
option time_string
option time_zone
option time_zone_string
option vendor_encapsulated_options
option vendor_class_identifier
option vendor_specific_information
option vendor_specific_information_encapsulated
option vendor_specific_information_suboption
option vendor_specific_information_suboption_encapsulated
option vendor_specific_information_suboption_encapsulated_encapsulated
option vendor_specific_information_suboption_encapsulated_encapsulated_encapsulated
EOF
		echo "✓ DHCP configuration created for Windows emulation"
	fi
	
	# Now that all packages are installed, we can safely block OpenWrt traffic
	echo "Installing persistent firewall rules..."
	if [ -f /etc/config/firewall.blue-merle ]; then
		# First verify the rules won't break anything
		echo "Verifying firewall rules..."
		if grep -q "option enabled '1'" /etc/config/firewall.blue-merle && \
		   grep -q "option target 'DROP'" /etc/config/firewall.blue-merle && \
		   grep -q "downloads.openwrt.org" /etc/config/firewall.blue-merle; then
			echo "✓ Firewall rules verified"
		else
			echo "Warning: Firewall rules verification failed - rules may be corrupted"
			exit 1
		fi
		
		# Merge our rules into the main firewall config
		cat /etc/config/firewall.blue-merle >> /etc/config/firewall
		rm -f /etc/config/firewall.blue-merle
		
		# Apply firewall rules
		echo "Applying firewall rules..."
		/etc/init.d/firewall restart
		sleep 2  # Wait for firewall to restart
		
		# Verify we can still access the router
		if ping -c 1 -W 2 127.0.0.1 >/dev/null 2>&1; then
			echo "✓ Firewall rules installed successfully (router still accessible)"
		else
			echo "Error: Firewall rules may have broken connectivity"
			# Emergency rollback
			for rule in block_openwrt_traffic block_openwrt_ntp block_opkg_repos; do
				uci -q delete firewall.$rule
			done
			uci commit firewall
			/etc/init.d/firewall restart
			exit 1
		fi
	else
		echo "Warning: Firewall rules file not found"
	fi
	
	# Configure switch button
	uci set switch-button.@main[0].func='sim'
	uci commit switch-button
	sleep 1  # Wait for UCI commit

	# Restart GL clients service
	/etc/init.d/gl_clients start
	sleep 2  # Wait for service to start

	echo "✓ Blue Merle Windows emulation package installed successfully"
	echo {\"msg\": \"Successfully installed Blue Merle\"} > /dev/ttyS0
endef

define Package/blue-merle/postrm
	#!/bin/sh
	uci set switch-button.@main[0].func='tor'
endef
$(eval $(call BuildPackage,$(PKG_NAME)))
