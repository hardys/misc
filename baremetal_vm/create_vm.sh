#!/bin/bash

set -euxo pipefail

source ../slemicro/common.sh
source common.sh

IMG_TO_USE=${IMG_TO_USE:-}

while getopts 'f:n:h' OPTION; do
	case "${OPTION}" in
		f)
			[ -f "${OPTARG}" ] && ENVFILE="${OPTARG}" || die "Parameters file ${OPTARG} not found" 2
			;;
		n)
			VMNAME="${OPTARG}"
			;;
		h)
			usage && exit 0
			;;
		?)
			usage && exit 2
			;;
	esac
done

if [ ! -d "${VMFOLDER}" ]; then
	mkdir ${VMFOLDER}
fi

# FIXME shardy workaround for DNS issues
IRONIC_HOST=${IRONIC_HOST:-$(vm_ip ${CLUSTER_VMNAME})}
if [ -z "${IRONIC_HOST}" ]; then
	die "Could not detect IRONIC_HOST - either set variable or ensure CLUSTER_VMNAME refers to a running VM"
fi

cd ${VMFOLDER}

echo "Creating virtual baremetal host"

qemu-img create -f qcow2 $VMNAME.qcow2 30G
#virt-install --name $VMNAME --memory 4096 --vcpus 2 --disk $VMNAME.qcow2 --boot uefi --import --network network=${VM_NETWORK} --osinfo detect=on --noautoconsole --print-xml 1 > $VMNAME.xml
virt-install --name $VMNAME --memory 4096 --vcpus 2 --disk $VMNAME.qcow2,bus=virtio --import --network network=${VM_NETWORK} --osinfo detect=on --noautoconsole --print-xml 1 > $VMNAME.xml
virsh define $VMNAME.xml

echo "Finished creating virtual node"
echo "Starting sushy-tools and httpd file server"

mkdir -p sushy-tools/
cat << EOF > sushy-tools/sushy-emulator.conf
SUSHY_EMULATOR_LISTEN_IP = u'0.0.0.0'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_SSL_CERT = None
SUSHY_EMULATOR_SSL_KEY = None
SUSHY_EMULATOR_OS_CLOUD = None
SUSHY_EMULATOR_LIBVIRT_URI = u'qemu:///system'
SUSHY_EMULATOR_IGNORE_BOOT_DEVICE = True
EOF

# run sushy-tools via podman if it's not already running
if [ $(sudo podman ps -f status=running -f name=sushy-tools -q | wc -l) -ne 1 ];then
  sudo podman run -d --rm --net host --privileged --name sushy-tools \
  --add-host boot.ironic.suse.baremetal:${IRONIC_HOST} --add-host api.ironic.suse.baremetal:${IRONIC_HOST} --add-host inspector.ironic.suse.baremetal:${IRONIC_HOST} \
  -v ./sushy-tools/sushy-emulator.conf:/etc/sushy/sushy-emulator.conf:Z \
  -v /var/run/libvirt:/var/run/libvirt:Z \
  -e SUSHY_EMULATOR_CONFIG=/etc/sushy/sushy-emulator.conf \
  -p 8000:8000 \
  quay.io/metal3-io/sushy-tools:latest sushy-emulator

  if [ "${VM_NETWORK}" != "default" ]; then
    # Open firewall to enable VM -> sushy access via the libvirt bridge
    sudo firewall-cmd --add-port=8000/tcp --zone libvirt
    sudo firewall-cmd --list-all --zone libvirt
  fi
fi
echo "Finished starting sushy-tools podman"

# Optionally cache an OS image for the BMH to reference
mkdir -p bmh-image-cache
IMG_FILENAME=$(basename ${IMG_TO_USE})
if [ ! -f bmh-image-cache/${IMG_FILENAME} ]; then
  curl -Lk ${IMG_TO_USE} > bmh-image-cache/${IMG_FILENAME}
  pushd bmh-image-cache
  md5sum ${IMG_FILENAME} | tee ${IMG_FILENAME}.md5sum
  popd
fi

if [ $(sudo podman ps -f status=running -f name=bmh-image-cache -q | wc -l) -ne 1 ]; then
  sudo podman run -dit --name bmh-image-cache -p 8080:80 -v ./bmh-image-cache:/usr/local/apache2/htdocs/ docker.io/library/httpd:2.4
  if [ "${VM_NETWORK}" != "default" ]; then
    # Open firewall to enable VM -> cache access via the libvirt bridge
    sudo firewall-cmd --add-port=8080/tcp --zone libvirt
    sudo firewall-cmd --list-all --zone libvirt
  fi
fi
echo "Finished starting sushy-tools podman"


# Get the IP of the libvirt bridge for VM_NETWORK
VIRTHOST_BRIDGE=$(virsh net-info ${VM_NETWORK} | awk '/^Bridge/ {print $2}')
IP_ADDR=$(ip -f inet addr show ${VIRTHOST_BRIDGE} | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')

# We automatically grab the mac address of each vm and the sushy-tools id of each vm
NODEID=$(curl -L http://$IP_ADDR:8000/redfish/v1/Systems/$VMNAME -k | jq -r '.UUID')
echo "Node UUID: $NODEID"

NODEMAC=$(virsh dumpxml $VMNAME | grep 'mac address' | grep -ioE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")
echo "Node MAC: $NODEMAC"

# We create custom BMH yamls using the data we collected earlier
# Note the metadata name must be in lowercase
BMH_NAME=$(echo "${VMNAME}" | tr '[:upper:]' '[:lower:]')
echo "Creating the BMH resource yaml file to the output folder ${VMFOLDER}"

function bmh_network_config() {
  if [ ! -z "${VM_STATIC_IP}" ]; then
cat <<EOF
  networkData:
    name: ${BMH_NAME}-networkdata
  preprovisioningNetworkDataName: ${BMH_NAME}-networkdata
EOF
  fi
}

function bmh_network_data() {
  cidr="${VM_STATIC_IP}/${VM_STATIC_PREFIX}"
  network=$(ipcalc --no-decorate -n ${cidr})
  netmask=$(ipcalc --no-decorate -m ${cidr})
  config="{
    \"links\": [
        {
            \"id\": \"eth0\",
            \"type\": \"phy\",
            \"ethernet_mac_address\": \"${NODEMAC}\"
        }
    ],
    \"networks\": [
        {
            \"id\": \"network0\",
            \"type\": \"ipv4\",
            \"link\": \"eth0\",
            \"ip_address\": \"${VM_STATIC_IP}\",
            \"netmask\": \"${netmask}\",
            \"network_id\": \"network0\",
            \"routes\": [
                {
                    \"network\": \"0.0.0.0\",
                    \"netmask\": \"0.0.0.0\",
                    \"gateway\": \"${VM_STATIC_GATEWAY}\"
                }
            ]
        }
    ],
    \"services\": [
        {
            \"type\": \"dns\",
            \"address\": \"${VM_STATIC_DNS}\"
        }

]
}
"
  echo -n "${config}" | base64 -w0
}

function bmh_userdata_config() {
  if [ ! -z "${VM_STATIC_IP}" -a ! -z "${VM_STATIC_IGNITION}" ]; then
cat <<EOF
  userData:
    name: ${BMH_NAME}-userdata
EOF
  fi
}

function bmh_user_data() {
  network_setup_service=$(cat ${SCRIPTDIR}/suse-network-setup.service | sed ':a;N;$!ba;s/\n/\\n/g')
  network_setup_script=$(cat ${SCRIPTDIR}/suse-network-setup.sh | jq -sRr @uri)
  config='
{
  "ignition": {
    "version": "3.3.0"
  },
  "passwd": {
    "users": [
      {
        "name": "root",
        "passwordHash": "$y$j9T$/t4THH10B7esLiIVBROsE.$G1lyxfy/MoFVOrfXSnWAUq70Tf3mjfZBIe18koGOuXB"
      }
    ]
  },
  "systemd": {
    "units": [{
      "name": "suse-network-setup.service",
      "enabled": true,
      "contents": "'${network_setup_service}'"
    }]
  },
  "storage": {
    "filesystems": [
      {
        "device": "/dev/disk/by-label/ROOT",
        "format": "btrfs",
        "mountOptions": [
          "subvol=/@/usr/local"
        ],
        "path": "/usr/local",
        "wipeFilesystem": false
      }
    ],
    "files": [{
      "path": "/usr/local/bin/suse-network-setup.sh",
      "mode": 488,
      "contents": { "source": "data:,'${network_setup_script}'" }
    }]
  }
}
'
  #echo ${config} > /tmp/shdebug.json
  #sudo podman run --pull=always --rm -i quay.io/coreos/ignition-validate:release - < /tmp/shdebug.json
  echo -n "${config}" | base64 -w0
}

function bmh_user_data_cloud_init() {
  config='
#cloud-config
chpasswd:
  list: |
    root:foo
  expire: false
ssh_pwauth: true
users:
  - name: shardy
    plain_text_passwd: foo
    lock_passwd: false
    groups: users, admin
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash
runcmd:
  - echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
  - systemctl restart ssh
'
  echo -n "${config}" | base64 -w0
}

cat << EOF > $VMNAME.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ${BMH_NAME}-credentials
type: Opaque
data:
  username: Zm9vCg==
  password: Zm9vCg==
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: ${BMH_NAME}
  labels:
    cluster-role: control-plane
spec:
  online: true
  image:
    url: "http://$IP_ADDR:8080/${IMG_FILENAME}"
    checksum: "http://$IP_ADDR:8080/${IMG_FILENAME}.md5sum"
  bootMACAddress: $NODEMAC
  bootMode: legacy
  rootDeviceHints:
    deviceName: ${DEVICE_HINT}
  bmc:
    address: redfish-virtualmedia+http://$IP_ADDR:8000/redfish/v1/Systems/$NODEID
    disableCertificateVerification: true
    credentialsName: ${BMH_NAME}-credentials
$(bmh_network_config)
$(bmh_userdata_config)
EOF

if [ ! -z "${VM_STATIC_IP}" ]; then
  cat << EOF >> $VMNAME.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ${BMH_NAME}-networkdata
type: Opaque
data:
  networkData: $(bmh_network_data)
EOF
fi

if [ ! -z "${VM_STATIC_IP}" -a ! -z "${VM_STATIC_IGNITION}" ]; then
  cat << EOF >> $VMNAME.yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: ${BMH_NAME}-userdata
type: Opaque
data:
  userData: $(bmh_user_data)
EOF
fi

echo "Done - now kubectl apply -f ${VMFOLDER}/$VMNAME.yaml"
