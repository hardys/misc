<div align="center">

# SUSE Edge misc

<p align="center">
  <img alt="SUSE Logo" src="https://www.suse.com/assets/img/suse-white-logo-green.svg" height="140" />
  <h3 align="center">SUSE Edge misc</h3>
</p>

| :warning: **This is an unofficial and unsupported repository. See the [official documentation](https://www.suse.com/solutions/edge-computing/).** |
| --- |

</div>

- [create\_vm.sh](#create_vmsh)
  - [Prerequisites](#prerequisites)
  - [Enviroment variables](#enviroment-variables)
  - [Usage](#usage)
- [delete\_vm.sh](#delete_vmsh)
  - [Prerequisites](#prerequisites-1)
  - [Enviroment variables](#enviroment-variables-1)
  - [Usage](#usage-1)
- [get\ip.sh](#get_ip)
  - [Prerequisites](#prerequisites-2)
  - [Enviroment variables](#enviroment-variables-2)
  - [Usage](#usage-2)

## create_vm.sh

This script creates a test VM on Linux or OSX using UTM and it is customized using cloud-init

The script will output the virtual terminal to connect to (using `screen` if needed) as well as the
IP that it gets from Libvirt or the OSX DHCPD service.


### Prerequisites

* `mkisofs`
* `qemu-img`

NOTE: They can be installed using `brew`. `envsubst` is available via the `gettext` package.

* [UTM 4.2.2](https://docs.getutm.app/) or higest (required for the scripting part)

* Download OS image
  * Download the a qcow cloud image which supports cloud-init, for example
    * [openSUSE Leap Image](https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.5/images/openSUSE-Leap-15.5.x86_64-NoCloud.qcow2)
    * [Ubuntu Jammy image](https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64-disk-kvm.img) (same as currently used for Equinix [metal3-demo](https://github.com/suse-edge/metal3-demo) testing)

### Enviroment variables

It requires a few enviroment variables to be set to customize it, the bare minimum are (see [env-minimal.example](env-minimal.example)):

```
OS_IMAGE_FILE="${HOME}/openSUSE-Leap-15.5.x86_64-NoCloud.qcow2"
# Folder where the VM will be hosted
VMFOLDER="/var/lib/libvirt/images"
```

They can be stored in the script basedir as `.env` or in any file and use the `-f path/to/the/variables` flag.

**NOTE**: There is a `vm*` pattern already in the `.gitignore` file so you can conviniently name your VM parameters file as `vm-foobar` and they won't be added to git. 

### Usage

```bash
$ ./create_vm.sh
VM started. You can connect to the serial terminal as: screen /dev/ttys001
Waiting for IP: ................
VM IP: 192.168.206.60
```

You could also use the `-f` parameter to specify a path where the variables are stored or `-n` to override the name of the VM to be used:

```bash
$ ./create_vm.sh -h
Usage: ./create_vm.sh [-f <path/to/variables/file>] [-n <vmname>]
```

### Static IPs

It is possible to deploy a VM with a static IP by setting the `VM_STATIC_IP` variable.

Optionally additional configuration may be specified:
* `VM_STATIC_GATEWAY` (defaults to `192.168.122.1`).
* `VM_STATIC_PREFIX` (defaults to `24`).
* `VM_STATIC_DNS` (defaults to the value of `VM_STATIC_GATEWAY`).

Note that in this configuration you must first disable DHCP for your libvirt network, which can be achieved via `virsh net-edit` to remove the `<dhcp>` stanza, then `virsh net-destroy` followed by `virsh net-start`

## delete_vm.sh

This script is intended to easily delete the previously SLE Micro VM created with the `create_vm.sh` script.

You can use the same `-f` or `-n` parameters as well.

:warning: There is no confirmation whatsoever!

### Prerequisites

* [UTM 4.2.2](https://docs.getutm.app/) or higest (required for the scripting part)

### Enviroment variables

The previous environment variables can be used but it requires a few less.

### Usage

```bash
$ ./delete_vm.sh
```

```bash
$ ./delete_vm.sh -h
Usage: ./delete_vm.sh [-f <path/to/variables/file>] [-n <vmname>]
```

## get_ip.sh

This script is intended to easily get the VM IP created with the `create_vm.sh` script.

You can use the same `-f` or `-n` parameters as well.

### Prerequisites

* A VM already deployed via the `create_vm.sh`
  
### Enviroment variables

The previous environment variables can be used but it requires a few less.

### Usage

```bash
$ ./get_ip.sh
192.168.205.2
```

```bash
$ ./get_ip.sh -h
Usage: ./get_ip.sh [-f <path/to/variables/file>] [-n <vmname>]

Options:
 -f		(Optional) Path to the variables file
 -n		(Optional) Virtual machine name
```
