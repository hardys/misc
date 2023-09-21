#!/bin/bash
set -euxo pipefail

# Adapted from https://github.com/openSUSE/combustion#perform-modifications-in-the-initrd-environment
nm_config() {
	umask 077 # Required for NM config
	mkdir -p /etc/NetworkManager/system-connections/
	cat >/etc/NetworkManager/system-connections/static.nmconnection <<-EOF
[connection]
id=static
type=ethernet
autoconnect=true

[ipv4]
method=manual
dns=${VM_GATEWAY_IP}
address1=${VM_STATIC_IP}/24,${VM_GATEWAY_IP}
EOF
}

if [ ! -z "${VM_STATIC_IP}" ]; then
	if [ "${1-}" = "--prepare" ]; then
		nm_config # Configure NM in the initrd
		exit 0
	fi
	nm_config # Configure NM in the system
fi
