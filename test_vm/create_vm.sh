#!/usr/bin/env bash
set -euo pipefail
BASEDIR="$(dirname "$0")"

source ${BASEDIR}/common.sh

usage(){
	cat <<-EOF
	Usage: ${0} [-f <path/to/variables/file>] [-n <vmname>]
	EOF
}

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

set -a
# Get the env file
source ${ENVFILE:-${BASEDIR}/.env}
# Some defaults just in case
CPUS="${CPUS:-2}"
MEMORY="${MEMORY:-4096}"
DISKSIZE="${DISKSIZE:-30}"
SSHPUB="${SSHPUB:-${HOME}/.ssh/id_rsa.pub}"
VMNAME="${VMNAME:-slemicro}"
EXTRADISKS="${EXTRADISKS:-false}"
VM_NETWORK=${VM_NETWORK:-default}
VM_NIC=${VM_NIC:-enp1s0}
VM_STATIC_IP=${VM_STATIC_IP:-}
VM_STATIC_PREFIX=${VM_STATIC_PREFIX:-24}
VM_STATIC_GATEWAY=${VM_STATIC_GATEWAY:-"192.168.122.1"}
VM_STATIC_DNS=${VM_STATIC_DNS:-${VM_STATIC_GATEWAY}}
set +a

# Check if the commands required exist
command -v qemu-img > /dev/null 2>&1 || die "qemu-img not found" 2

# Create the image file
mkdir -p ${VMFOLDER}
cp ${OS_IMAGE_FILE} ${VMFOLDER}/${VMNAME}.qcow2
qemu-img resize -f qcow2 ${VMFOLDER}/${VMNAME}.qcow2 ${DISKSIZE}G > /dev/null

cat > ${VMFOLDER}/${VMNAME}-user-data.yaml <<EOF
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
    ssh_authorized_keys:
      - $(cat ${SSHPUB})
runcmd:
  - echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
  - systemctl restart ssh
EOF

if [ ! -z "${VM_STATIC_IP}" ]; then
  cat > ${VMFOLDER}/${VMNAME}-network-config.yaml <<EOF
instance-id: test
local-hostname: test
network:
  version: 2
  ethernets:
    ${VM_NIC}:
      dhcp4: no
      addresses: [${VM_STATIC_IP}/${VM_STATIC_PREFIX}]
      nameservers:
           addresses: [${VM_STATIC_DNS}]
      routes:
      - to: 0.0.0.0/0
        via: ${VM_STATIC_GATEWAY}
EOF
else
  cat > ${VMFOLDER}/${VMNAME}-network-config.yaml <<EOF
instance-id: test
local-hostname: test
network:
  version: 2
  ethernets:
    ${VM_NIC}:
      dhcp4: yes
EOF
fi

if [ $(uname -o) == "GNU/Linux" ]; then
	virt-install --name ${VMNAME} \
		--noautoconsole \
		--memory ${MEMORY} \
		--vcpus ${CPUS} \
		--disk ${VMFOLDER}/${VMNAME}.qcow2 \
		--import \
		--network network=${VM_NETWORK} \
		--os-variant=ubuntu22.04 \
		--cloud-init user-data=${VMFOLDER}/${VMNAME}-user-data.yaml,network-config=${VMFOLDER}/${VMNAME}-network-config.yaml
	echo "VM ${VMNAME} started. You can connect to the serial terminal as: virsh console ${VMNAME}"
	echo -n "Waiting for IP..."
	timeout=180
	count=0
	VMIP=""
	while [ -z "${VMIP}" ]; do
			sleep 1
			count=$((count + 1))
			if [[ ${count} -ge ${timeout} ]]; then
				break
			fi
			echo -n "."
			VMIP=$(vm_ip ${VMNAME})
	done
else
	die "VM not deployed. Unsupported operating system" 2
fi

printf "\nVM IP: ${VMIP}\n"
