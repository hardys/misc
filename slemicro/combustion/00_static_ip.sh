#!/bin/bash
set -euxo pipefail

if [ ! -z "${VM_STATIC_IP}" ]; then
	# The NM configuration isn't activated so we have to bring the NIC up manually
	# otherwise subsequent steps e.g registration will fail
	ip addr add ${VM_STATIC_IP}/24 dev eth0
	ip route add default via ${VM_GATEWAY_IP}
	echo "nameserver ${VM_GATEWAY_IP}" > /etc/resolv.conf

	umask 077 # Required for NM config
	mkdir -p /etc/NetworkManager/system-connections/
	cat >/etc/NetworkManager/system-connections/eth0.nmconnection <<-EOF
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=true

[ipv4]
method=manual
dns=${VM_GATEWAY_IP}
address1=${VM_STATIC_IP}/24,${VM_GATEWAY_IP}
may-fail=false
EOF
fi
