#!/usr/bin/env bash
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

die(){
	echo ${1} 1>&2
	exit ${2:-1}
}

usage(){
	cat <<-EOF
	Usage: ${0} [-f <path/to/variables/file>] [-n <vmname>]
	EOF
}

set -a
# Source the .env file if it exists
ENVFILE=${ENVFILE:-${SCRIPTDIR}/.env}
[ -f ${ENVFILE} ] && source ${ENVFILE}

# Some defaults if no .env is specified
VMFOLDER=${VMFOLDER:-"/var/lib/libvirt/images"}
VM_NETWORK=${VM_NETWORK:-"default"}
CPUS="${CPUS:-2}"
MEMORY="${MEMORY:-2048}"
DISKSIZE="${DISKSIZE:-30}"
CLUSTER_VMNAME="${CLUSTER_VMNAME:-SLEMicro}"
VMNAME="${VMNAME:-BareMetalHost}"
EXTRADISKS="${EXTRADISKS:-false}"
DEVICE_HINT=${DEVICE_HINT:-"/dev/vda"}
VM_STATIC_IP=${VM_STATIC_IP:-}
VM_STATIC_PREFIX=${VM_STATIC_PREFIX:-24}
VM_STATIC_GATEWAY=${VM_STATIC_GATEWAY:-"192.168.122.1"}
VM_STATIC_DNS=${VM_STATIC_DNS:-${VM_STATIC_GATEWAY}}
VM_STATIC_IGNITION=${VM_STATIC_IGNITION:-}
set +a
