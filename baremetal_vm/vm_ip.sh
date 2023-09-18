#!/usr/bin/env bash
set -euo pipefail
source common.sh

QUIET=""
qecho(){
	if [ -z "${QUIET}" ]; then
		echo -n ${1}
	fi
}


while getopts 'f:n:qh' OPTION; do
	case "${OPTION}" in
		f)
			[ -f "${OPTARG}" ] && ENVFILE="${OPTARG}" || die "Parameters file ${OPTARG} not found" 2
			;;
		n)
			VMNAME="${OPTARG}"
			;;
		q)
			QUIET="true"
			;;
		h)
			usage && exit 0
			;;
		?)
			usage && exit 2
			;;
	esac
done

if [ $(uname -o) == "Darwin" ]; then
	OUTPUT=$(osascript <<-END
	tell application "UTM"
		set vm to virtual machine named "${VMNAME}"
		set config to configuration of vm
		get address of item 1 of network interfaces of config
	end tell
	END
	)

	VMMAC=$(echo $OUTPUT | sed 's/0\([0-9A-Fa-f]\)/\1/g')

	timeout=180
	count=0

	qecho "Waiting for IP: "
	until grep -q -i "${VMMAC}" -B1 -m1 /var/db/dhcpd_leases | head -1 | awk -F= '{ print $2 }'; do
		count=$((count + 1))
		if [[ ${count} -ge ${timeout} ]]; then
			break
		fi
		sleep 1
		qecho "."
	done
	VMIP=$(grep -i "${VMMAC}" -B1 -m1 /var/db/dhcpd_leases | head -1 | awk -F= '{ print $2 }')
elif [ $(uname -o) == "GNU/Linux" ]; then
	qecho "Waiting for IP..."
	timeout=180
	count=0
	while [ $(virsh domifaddr ${VMNAME} | awk -F'[ /]+' '/ipv/ {print $5}' | wc -l) -ne 1 ]; do
			count=$((count + 1))
			if [[ ${count} -ge ${timeout} ]]; then
				break
			fi
			sleep 1
			qecho "."
	done
	VMIP=$(virsh domifaddr ${VMNAME} | awk -F'[ /]+' '/ipv/ {print $5}' )
else
	die "Unsupported operating system" 2
fi

if [ -z "${QUIET}" ]; then
	printf "\nVM IP: ${VMIP}\n"
else
	echo "${VMIP}"
fi
