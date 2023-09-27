#!/bin/bash

# Attempt to statically configure a nic in the case where we find a network_data.json
# In a configuration drive

CONFIG_DRIVE=$(blkid --label config-2)
if [ -z "${CONFIG_DRIVE}" ]; then
  echo "No config-2 device found, skipping network configuration"
  exit 0
fi

mount -o ro $CONFIG_DRIVE /mnt

NETWORK_DATA_FILE="/mnt/openstack/latest/network_data.json"

## Function to convert netmask to CIDR notation
IPprefix_by_netmask () {
   c=0 x=0$( printf '%o' ${1//./ } )
   while [ $x -gt 0 ]; do
       let c+=$((x%2)) 'x>>=1'
   done
   echo $c ;
}


## Verify if file Network Data exists
if [ ! -f $NETWORK_DATA_FILE ]; then
  echo "File $NETWORK_DATA_FILE not found, skipping network configuration"
  exit 0
fi

## Verify if jq is installed
if ! command -v jq &> /dev/null
then
  echo "jq could not be found!"
  exit 1
fi

## Verify if file Network Data is a json file
if ! jq -e . >/dev/null 2>&1 <<<$(cat $NETWORK_DATA_FILE); then
  echo "File $1 is not a json file!"
  exit 1
fi


## Verify if file Network Data is a valid json file
if ! jq empty $NETWORK_DATA_FILE >/dev/null 2>&1; then
  echo "File $1 is not a valid json file!"
  exit 1
fi

## Extract network data info from json file
MAC_ADDRESS=$(jq -r '.links[0].ethernet_mac_address' $NETWORK_DATA_FILE)
IFNAME=$(jq -r '.links[0].id' $NETWORK_DATA_FILE)
IP_ADDRESS=$(jq -r '.networks[0].ip_address' $NETWORK_DATA_FILE)
NETMASK=$(jq -r '.networks[0].netmask' $NETWORK_DATA_FILE)
NETMASKCIDR=$(IPprefix_by_netmask $NETMASK)
GATEWAY=$(jq -r '.networks[0].routes[0].gateway' $NETWORK_DATA_FILE)
DNS=$(jq -r '.services[0].address' $NETWORK_DATA_FILE)

umount /mnt

echo "MAC_ADDRESS: $MAC_ADDRESS"
echo "IFNAME: $IFNAME"
echo "IP_ADDRESS: $IP_ADDRESS"
echo "NETMASK: $NETMASK"
echo "NETMASKCIDR: $NETMASKCIDR"
echo "GATEWAY: $GATEWAY"

if ! ip -4 a show ${IFNAME} up | grep "state UP"; then
  echo "Configuring $IFNAME with static IP from network_data.json"
#  ip addr add ${IP_ADDRESS}/${NETMASKCIDR} dev ${IFNAME}
#  ip route add default via ${GATEWAY}
#  echo "nameserver ${DNS}" >> /etc/resolv.conf
  nmcli con add type ethernet con-name $IFNAME ifname $IFNAME ip4 ${IP_ADDRESS}/${NETMASKCIDR} gw4 ${GATEWAY}
  nmcli con mod $IFNAME ipv4.dns $DNS
  nmcli con up $IFNAME ifname $IFNAME
fi
