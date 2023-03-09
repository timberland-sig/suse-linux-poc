# NVMe-of/TCP Boot with openSUSE Virtual Machines

## DISCLAIMER

These instructions have been created with diligence and
are provided in the hope that they will be useful, but **without guarantee of
any kind**. **Use at you own risk.** It is **strongly discouraged** to run the
commands  below, in particular the "Basic Walkthrough for Developers",
on production systems.

## Basic Walkthrough for Developers

**Important:** This section is intended for *developers and advanced users* who want to
understand how the setup is built from ground up. If this doesn't apply
to you, please skip this section and go directly to the [Full Proof-of-Concept](#full-proof-of-concept)
instead.

**This entire section assumes that you work with root rights.**

### System Requirements

Install QEMU/KVM, the QEMU bridge helper, nvme-cli, and curl. 
Under openSUSE, you would do it like this:

    zypper install qemu-kvm qemu-tools nvme-cli curl

### Preparations

Set a few shell variables that you will use frequently.

    # The working directory where you will store files for the PoC,
    DIR=$HOME/nvmetest
	# Disk image to install on
    DISK=$DIR/disk01
	# Name of the Bridge device to use
	BRIDGE=br_test
	# IPv4 subnet to use - shouldn't overlap with other networks on your host
    NET=192.168.35
	# The subsystem NQN under which the disk will be exported
    NQN=nqn.2023-01.org.nvmexpress.boot.poc.simple:subsys01
	# The MAC address of your VM
    MAC=52:54:00:12:34:56
	# The NVMe Host NQN of your VM
    HOSTNQN=nqn.2023-01.org.nvmexpress.boot.poc.simple:vm01

### Setting up the Network Bridge

Create the bridge device, configure an IP address, and allow qemu
to connect to it. If you are running a firewall, add this interface 
to a zone that permits all traffic. The example below shows how to do this
with firewalld.

    ip link add "$BRIDGE" type bridge stp_state 0
    ip link set "$BRIDGE" up
    ip addr add $NET.1/24 dev "$BRIDGE"
    echo "allow $BRIDGE" >/etc/qemu/bridge.conf
    firewall-cmd --zone trusted --add-interface=br_test

Change into your working directory and create an empty disk image.

    mkdir -p $DIR
    cd $DIR
    truncate -s 20G "$DISK"

### Configuring the NVMe Target

Load kernel modules for the NMVe target, create the NQN, and link it to the
disk you just created. Allow any host to connect[^simple].

    modprobe nvmet nvmet-tcp
    cd /sys/kernel/config/nvmet/subsystems
    mkdir $NQN
    cd $NQN
    echo 1 > attr_allow_any_host
    mkdir namespaces/1
    echo "$DISK" > namespaces/1/device_path
    echo 1 > namespaces/1/enable

[^simple]: We're creating the simplest possible setup here.

Create a TCP/IPv4 NVMe target port on the subnet of your bridge, and link the
previously created subsystem to it.

    cd /sys/kernel/config/nvmet/ports
    mkdir 1
    cd 1
    echo tcp > addr_trtype
    echo ipv4 > addr_adrfam
    echo $NET.1 > addr_traddr
    echo 4420 > addr_trsvcid
    ln -s "/sys/kernel/config/nvmet/subsystems/$NQN" subsystems

Your NVMe target is now operational. You can test it like this:

    modprobe nvme-fabrics
    nvme discover -t tcp -a $NET.1 -s 4420

This command should display two entries, one of the referencing the NQN
defined above.

### Downloading the NVMe-oF Enabled OVMF Firmware

Change back to your working directory, download and unpack the NVMe-oF enabled
EDK2 firmware, and make a copy of the UEFI variable store[^ovmf_url]:

    cd $DIR
    curl -s -L -o ovmf.zip https://github.com/timberland-sig/edk2/releases/download/release-9e63dc0/timberland-ovmf-release-9e63dc0.zip
    unzip ovmf.zip
	cp OVMF_VARS.fd vm_vars.fd

The ZIP archive contains 3 files: `OVMF_CODE.fd` (the actual firmware image),
`OVMF_VARS.fd` (an empty UEFI non-volatile variable store), and
`NvmeOfCli.efi` (the EFI utilitiy used to load an NVMe-oF boot attempt
configuration into UEFI variables). Move the `NvmeOfCli.efi` tool into a separate
directory.

    mkdir efi
    mv NvmeOfCli.efi efi
    
[^ovmf_url]: You can obtain the URL of the latest release with the command
	`curl -s https://api.github.com/repos/timberland-sig/edk2/releases/latest |  grep browser_download_url`. 

### Creating an NVMe-oF Boot Attempt Configuration

Create an attempt configuration[^config] and a `startup.nsh` file in the
same directory where you stored `NvmeOfCli.efi`:

    cat >efi/config <<EOF
    HostNqn:$HOSTNQN
    HostId:01234567-89ab-cdef-fedc-ba9876543210
    \$Start
    AttemptName:Attempt1
    HostName:testvm
    MacString:$MAC
    TargetPort:4420
    Enabled:1
    IpMode:0
    LocalIp:$NET.61
    SubnetMask:255.255.255.0
    Gateway:$NET.1
    TargetIp:$NET.1
    NQN:$NQN
    ConnectTimeout:6000
    DnsMode:FALSE
    \$End
    EOF
    
    cat >efi/startup.nsh <<EOF
    NvmeOfCli setattempt Config
    stall 1000000
    exit
    EOF

[^config]: This is a static IPv4 configuration, the simplest possible
    case. You can find templates for other configuration types in the `config` subdirectory.

### Start the Test Virtual Machine

Now it's time to run your VM. To simplify matters, define an alias with the
commonly used options[^vga]:

    alias qq="\
	qemu-system-x86_64 -M q35 -m 1G -accel kvm -cpu host \
      -nographic -device virtio-rng -boot menu=on,splash-time=2000 \
      -drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
      -drive if=pflash,format=raw,file=vm_vars.fd \
      -netdev bridge,id=n0,br=$BRIDGE -device virtio-net-pci,netdev=n0,mac=$MAC"

Run this VM with the `efi` directory as a small pseudo-disk.
**Hit `ESC` quickly after typing the following command, to skip PXE boot.
If you miss and PXE starts, quit the VM by typing `Ctrl-a x` and try again.**

    qq -drive format=raw,file=fat:rw:./efi

In the main menu, select `Boot Manager`, and boot `EFI Internal Shell`. Do not
interrupt, `startup.nsh` will run, and the main menu will be shown again.
Shut down the VM using `Ctrl-a x`.

#### What happened here?

The `startup.nsh` file is auto-executed by the EFI shell. It runs
`NvmeOfCli.efi`, which loads the configuration from the `config` file and
stores it in a non-volatile EFI variable. On the subsequent boot, the EFI NVMe-oF/TCP driver will find
this variable, set up the network as configured, and attempt to connect to the
target subsystem. If successful, it will provide a boot menu entry and will
store the boot parameters in the `NBFT` ACPI table, from where the operating
system will be able to retrieve it later.

### Install openSUSE Leap

Download an installation image of some Linux distribution. openSUSE Leap 15.5 beta
is recommended, because it supports installation on NVMe-oF out of the box.
If you have an image already, copy or link it to `dvd.iso`. Otherwise,

    curl -s -L -o dvd.iso https://download.opensuse.org/distribution/leap/15.5/iso/openSUSE-Leap-15.5-DVD-x86_64-Current.iso

Now boot the VM from this DVD:

    qq -cdrom dvd.iso

The `qq` alias above uses `-nographic`[^vga], so you need to type `t` at
the grub prompt, move the cursor to the `Installation` line, type `e` to edit
the command line, and add the boot parameter `console=ttyS0` to the line starting with
`linux`, in order to be able to use the text console during installation.
Hit `Ctrl-x` to start the installation, and follow the usual
installation procedure[^beta]. The system will eventually reboot, 
and the installed system should boot successfully.

### Examining the Booted System

You can examine the status with a few shell commands:

    nvme show-nbft -H -o json
    nvme show-nbft -s -o json
    nvme list-subsys
    ip addr show nbft0
    wicked ifstatus nbft0 # this is openSUSE specific

Note that the NBFT-configured network interface is called `nbft0`.
The DVD image is not needed any more, subsequent invocations of the VM can be
done simply the command `qq`.

**Note:** the "successful boot" above could be a false positive. **dracut**
adds command line parameters for network and NVMe target setup
in the initial RAM disk that cause the boot to
succeed, even without NBFT support in the OS. To verify that the
firmware-provided boot parameters are indeed used rather than dracut's static ones, 
you can change the firmware configuration e.g. by modifying the host or 
target IP address or the subsystem NQN[^target]. 
To do this, you need to run `startup.nsh` from the "EFI disk" again,
which will require typing `ESC` quickly to enter the EFI menu and starting the
EFI shell (see above). After running `startup.nsh` with a modified configuration file
and resetting the system, the system should boot, and the configuration changes
should be visible after booting in the OS. If this is the case, you can be
certain that paramters from the NBFT have indeed be applied.

[^target]: You could use the well-defined NQN
    `nqn.2014-08.org.nvmexpress.discovery`, for example.

## Where to go from here

The very simple configuration shown here is just a starting point. The
configuration can (and should) be changed in many ways. Advanced users can
achieve a lot by modifiying the instructions
in this walkthrough. But for more complex setups, it is recommended to use the full
proof-of-concept setup instead, as described in [the following section](#full-proof-of-concept).

# Full Proof-of-Concept

## Features

* Operated by simple `make` commands
* Automated network setup with bridge and optionally with OpenVSwitch and VLAN
* NVMe target is running as a vagrant VM
* Automated server setup matching the network setup
* Multiple VMs with different configurations can be set up in parallel
* Proper ACL settings on the NVMe server
* IPv4 and IPv6
* DHCP server, DNS server
* NVMe discovery
* Support for creating libvirt domains
* Support for changing configurations easily and consistently to avoid failure
  due to common configuration mistakes.

## Prerequisites

### Packages

* libvirt, qemu-kvm, make, git, wget, curl, jq, mkisofs, dnsmasq, sudo
* vagrant, vagrant-libvirt, ansible, python-jmespath, python-netaddr
* optional: openvswitch
* optional (for running test VM under libvirt): xsltproc, mtools
* For newer versions of ansible, the collections `ansible.posix` and/or
  `community.general` may be required (install with `ansible-galaxy`).

### Daemons

The libvirt and (if used) the OpenVSwitch daemon must be running.

### Enabling Rootless Operation

(If you intend to run everything as root, skip this section).

While much of the Proof of Concept can be run rootless, some commands require
superuser priviliges, in particular:

* network setup (bridges, IP configuration, etc.)
* running qemu with OVS interfaces.

Your user ID should also be able to run virtual machines with both qemu and
libvirt. On most modern Linux distributions, this is granted by adding the
user to the groups `qemu` (or `kvm`) and `libvirt`, respectively.

Run **make help-rootless** to print additional configuration hints for your
environment, to enable passwordless root access for those commands
that need it. Apply the suggestions. You don't have to apply the `sudoers`
configuration, but if you don't, you may have to type the root password
frequently. *Adding the entry in `/etc/qemu/bridge.conf` is mandatory*.

## Setting up the Environment

The PoC is driven by the **make** command. Run **make help** for a quick overview.
At the first **make** invocation, two configuration files `env-config.mk` and
`vm-config.mk` will be created. By default, the test environment will create
a bridge `br_nvme` with two subnets with the IP ranges 192.168.49.0/24 and
fddf:d:f:49::/64. If this overlaps with existing networks in your environment,
change `SUBNET_BASE` in `env-config.mk`[^ovs].

[^ovs]: If you want to use OpenVSwitch (OVS), 
	set `NVME_USE_OVS` to 1. In this case, additional IP ranges 192.168.50.0/24, 
	192.168.51.0/24, fddf:d:f:50::/64, and fddf:d:f:51::/64 will be
	created. Again, modify `env-config.mk` if necessary to avoid overlapping IP ranges.

The default setup will create two NVME subsystems and export them to one
client VM each.

Save your configuration, and run

    make server-up

This will set up the network, start the vagrant server VM, and configure it to
serve a namespace (disk) for your first client VM. The server has the IP
addresses 192.168.49.10 and fddf:d:f:49::10[^ovs1]. At the end of the
procedure, the configured target ports and subsystems will be printed to the screen.

[^ovs1]: plus equivalent addresses ending in "10" for the OVS subnets, if configured. 

To test the server, run (as root)

    nvme discover -t tcp -a 192.168.49.10  -s 4420 -q nqn.2014-08.org.nvmexpress:uuid:$UUID

where UUID has been printed by the previous command, or can be found in the
file `uuid-leap.mk`[^hostnqn].

[^hostnqn]: Without the `-q` argument, `nvme discover` will print no
    subsystem, because ACLs on the server restrict access.

## Installing a Client Virtual Machine

**Important: kill a hanging qemu VM with `Ctrl-b x`.**[^ctrlb]

[^ctrlb]: By default, this PoC uses `Ctrl-b x` rather than qemu's default
    `Ctrl-a x`, in order to be able to run the PoC under **screen**.

The settings for the client are in `vm-config.mk`. Leaving the defaults as-is
should work for your first installation. You can change the settings later.

The PoC uses openSUSE Leap. Leap 15.4 and 15.5 are supported (`VERSION` in
`vm-config.mk`). If you have an installation medium (DVD) for the configured
openSUSE Leap version around, copy or link it to
`openSUSE-Leap-$(VERSION)-DVD-x86_64-Media.iso` in the top directory.
Otherwise, the next command will download the image from the internet.

The following command will download and build all necessary artifacts and start the VM.
Most importantly, it will build a small EFI disk with the `NvmeOfCli.efi`
executable and a `startup.nsh` script. This disk must be booted to set the
NVMe-oF boot attempt variables. Run 

    make inst

**As soon as the VM starts, hit the `ESC` key**. If you miss it and PXE boot
starts, kill the VM with `Ctrl-b x` and try again. In the EFI main menu,
select `Boot Manager → EFI Internal Shell`. Don't interrupt and let the shell
execute `startup.nsh`. Back in the main menu, quit the VM with `Ctrl-b x`.
See [What happened here?](#what-happened-here) for an explanation of this step.

The VM will start again. This time, just wait until you see the boot menu from
the openSUSE DVD (you my have to type `t` first to display the menu on serial
console). Move cursor to `Installation`, type `e` to edit the line,
and add `console=ttyS0` on the line starting with `linux`[^vga]. Type `Ctrl-x`
to start the installation.

[^vga]: Alternatively, set `VM_VGA_FLAGS` in `vm-config.mk` to
    enable a VGA console and graphical UI for qemu.

Follow the installation procedure as usual. *Do not enable online
repositories*, as by default the VM runs in an isolated network without
internet connectivity. The NVMeoF disk should be detected
as `/dev/nvme0n1`. Eventually, the system will reboot, and you will be able to
log in and examine the result as shown in [Examining the booted system](#examining-the-booted-system).

After shutdown, you can boot the installed system with **make qemu**.

## Modifying the Configuration

Find the most important settings in `vm-config.mk`. You can modify them in
this file, or (for temporary changes) you can set the variables directly on
the `make` command line, like this:

    make VM_NAME=host2 SUBSYS=02 CONFIG=Static6 DISCOVERY=1

The individual settings are:

* `CONFIG`: an attempt configuration template from the `config`
  subdirectory. `Static4` is a static IPv4 configuration, `Dhcp6` an IPv6
  configuration using DHCP, etc.
* `DISCOVERY`: set to 1 to use NVMe discovery rather than expclicit storage
  subsystem reference in the NVMe boot attempt.
* `VM_NAME`: If you change this, a new UUID will be generated, and you'll work
  with a different VM. Make sure to set `SUBSYS` to a different number if you
  want to use the old and new VM in parallel.
* `SUBSYS`: A 2-digit number indicating the subsystem on the server which
  should be exported to this VM. It must be no larger than
  `NVME_MAX_NAMESPACES` in `env-config.mk`.
* `VERSION`: The openSUSE version to install. 15.4 or 15.5 are supported. 15.5
  contains native support for NVMe-oF/TCP boot, whereas 15.4 needs a driver
  update disk (DUD) with updated packages. The PoC scripts will build the DUD
  automatically.
* `VLAN_ID`: (only in OVS setups with `VM_NETWORK_TYPE=ovs`): If set to 1
  (actually, `$(OVS_VLAN_ID)`), a tagged VLAN with VLAN ID 1 will be
  configured on the client VM.
* `USE_GW`: Add a gateway. This makes it possible to configure a target that
  is outside the directly attached subnet of the VM. Actually doing that
  requires configuring the target IP address in `TARGET` explicitly; this
  is not automated. `USE_GW` also influences the **dnsmasq** configuration; it
  requires a `make net-down; make server-up` sequence.

After changing the attempt configuration, you will need to:

* run `make server-config` to make sure the server has the correct settings
  for `VM_NAME` and `SUBSYS`.
* boot the VM into EFI shell
  again (hitting `ESC` quickly after boot), run the (automatically
  regenerated) `startup.nsh` script, and reset the system once to actually
  use the changed settings.

### Configuring the DHCP Root-path Option

Default configuration for **dnsmasq**:

    dhcp-range=set:br_nvme_4,192.168.49.129,192.168.49.254,300
    dhcp-option=tag:br_nvme_4,option:root-path,"nvme+tcp://vagrant-nvmet.br_nvme:4420/nqn.2014-08.org.nvmexpress.discovery//"

If `CONFIG := DhcpRoot4` is used, this root path should be retrieved by the
VM. In the given format, it requires DNS resolution and successful NVMe
discovery by the client VM.

If you want to play with different DHCP root path settings, you can do so by
creating a file `network.conf` in the top level directory, and setting the
shell variable `DNSMASQ_EXTRA_OPTS`, like this:

    DNSMASQ_EXTRA_OPTS="\
    dhcp-host=52:54:00:a2:a7:b2,set:host1,192.168.49.97,host1
    dhcp-option=tag:host1,option:root-path,\"nvme+tcp://192.168.50.10:4420/nqn.2022-12.org.nvmexpress.boot.poc:zeus.vagrant-nvmet.subsys03//\""

This requires running `make net-down; make server-up`. For temporary changes
you can also kill the current **dnsmasq** instance, edit the configuration
file, and start another **dnsmasq** for the test network:

    kill $(cat /run/dnsmasq/dnsmasq-nvmeof.pid)
    vi /run/dnsmasq/dnsmasq-nvmeof.conf  # add changes as described above
    dnsmasq --pid-file=/run/dnsmasq/dnsmasq-nvmeof.pid -C /run/dnsmasq/dnsmasq-nvmeof.conf

The general format of the root path is

    nvme+tcp://${TARGET}[:${PORT}]/${SUBSYSNQN}/${NID}

The `NID` (namespace ID) may be empty, in which case the namespace it will be
chosen automatically. For an emtpy `NID` use "/" (like above) or "0". A real
`NID` has the format `urn:uuid:cc3f2135-f931-4569-baea-0eee7113a526`.
`TARGET` may be given as IPv4 address or host name. The `SUBSYSNQN` can be the
well-known discovery NQN `nqn.2014-08.org.nvmexpress.discovery`, in which case
the `NID` should be empty, and the host will an attempt a discovery to the
given target. **Note:** the default port for discovery is 8009, port 4420
needs to be specifically set in the root-path to use it.

### Configuring IPv6

NVMVe-oF/TCP over IPv6 doesn't work perfectly in EDK2 yet. Be prepared for
sporadic hangs or timeouts. This is work in progress.

Unlike IPv4, the network configuration is not taken from the `CONFIG` file. It must be
configured in the EFI UI instead: `Device Manager` → `Network Device List` →
MAC address → `IPv6 Network Configuration` → `Enter Configuration Menu`; then
set either `Policy: automatic` (for DHCP or IPv6 SLAAC), or set `Policy:
manual` and add IPv6 addresses under `Advanced Configuration`.

Note that the `CONFIG` file is still necessary for configuring target
parameters.

### Advanced Configuration

Examine the [Makefile](Makefile) and the scripts [qemu.sh](qemu.sh), [libvirt.sh](libvirt.sh), and
[network/setup.sh](network/setup.sh) for further configuration options, which are all in
`CAPITAL LETTERS` and can usually be set via environment variables.
The Makefile uses environment variables (`export` statements) to
control the configuration of the helper scripts, but the scripts have
additional variables that enable more fine-grained control.

`qemu.sh` and `network/setup.sh` allow customizations in config files `qemu.conf` (or
`qemu-$VM_NAME-conf`) and `network.conf` in the to directory, respectively.
See [Configuring the DHCP Root-path Option](#configuring-the-dhcp-root-path-option) above for an example, 
and for instructions to restart **dnsmasq**.

Some variables which are derived in the Makefile, such as `IPADDR`, `TARGET`,
and `GATEWAY`, can be set in `vm-config.mk` instead, overriding the
derived values.

The server configuration can be modified in the ansible input file
`nvmet-server/group_vars/nvme_servers` (YaML format). This file is in part
auto-generated by the Makefile, but customizations are allowed. For example,
the `all_nvme_subsystems` variable can be modified to assign multiple namespaces
to one host.

## Using Libvirt

Using `make libvirt` instead of `make inst` will create a libvirt VM called
`nvmeof-$VM_NAME`, which can be started, stopped and otherwise manipulated
using **virt-manager** as  usual. This requires **mtools** and **xsltproc**.

When using libvirt, you should use the **virt-manager** UI to modify the
settings of the test VM (the network bridge, CD-ROM drive, etc.). Run
`make efidisk.img` for changing attempt parameters on the EFI disk.

You can also run `make libvirt` *after* `make inst`. Actually, the libvirt
VM and **make qemu** will use the same non-volatile EFI store and NVMeoF
subsystem, so *make sure you don't run both at the same time*.

## Cleaning Up

**Note:** None of the commands below stop any running client VMs. You need to
do this manually.

* `make vars-clean`: removes the non-volatile EFI variable store, which will
  be regenerated empty the next time the VM is started.
* `make libvirt-clean`: undefines the libvirt VM for `VM_NAME`.
* `make server-down`: shuts down the nvme server.
* `make net-down`: shuts down the nvme server and the test network.
* `make server-destroy`: removes the vagrant server instance, which will be
  recreated with the next `make server-up`. Run `make server-destroy` if you
  want to make changes in `env-config.mk`. Note that this **does not** clean
  out the served namespaces (disks) of the server, which are stored in the
  libvirt storage pool `default` (usually `/var/lib/libvirt/images`). They
  will be re-used by the new server after `make server-up`.
* `make all-clean`: cleanup everything, except the namespaces (see above).

## Troubleshooting

Use `make V=1` to show details of the actions carried out by `make`. Use `V=2`
to enable verbose output of helper scripts, vagrant, and ansible.

# How Does This Work?

The bulk of the logic that enables NVMeoF boot, as far as Linux is concerned,
is in **nvme-cli**. Other tools basically just need to consume the output of
`nvme-cli show-nbft`, create a networking setup according to these settings,
and run `nvme-cli connect-nbft`. This must be done

1. during installation, before entering the partitioning dialog,
2. during boot of the installed system

## Setup in the installed system

### Distributions using dracut

On distributions using **dracut** for creating the initial RAM filesystem,
dracut's `nvmf` module has been extended for NBFT support. The logic is very
similar to the iBFT-parsing logic in the `iscsi` module.

- In the `cmdline` step (the first step executed by dracut), the NBFT ACPI
  table is detected and parsed, and the content is translated into `ip=...`
  directives that are understood by dracut. Furthermore, `rd.neednet=1` is
  set, and `ifname` directives are created to make sure the correct interfaces
  are configured in the initqueue stage.
- In the `pre-udev` step, udev rules are generated to rename network
  interfaces according to the `ifname` directives, and bring these interfaces up.
- In the `udev` stage, the previously generated rules are executed.
- In the `initqueue` stage, dracut attempts to run `nvme connect-nbft` after
  the udev queue has settled. Because `rd.neednet` is set, dracut should
  try to bring up the configured interfaces, and once this is finished, the
  initqueue hooks will be called and the NVMeoF connetion established.
  
This approach requires no changes in dracut's network setup modules.
Thus it *should* work with all network backends that dracut supports.

### Other distributions

TBD.

## Setup during installation

This part depends strongly on the distribution and the capabilities of the
installation program.

### openSUSE Leap

openSUSE Leap 15.5 has native support for installing on NVMe-oF/TCP in its
installation programs (`linuxrc` and `YaST`). Presence of an NBFT table is
automatically detected.

On openSUSE Leap 15.4, he driver update disk (DUD) concept[^dud] is leveraged
to install updated packages for **nvme-cli**, **dracut** and their
dependencies. These packages are not official Leap 15.4 packages, but they
are compiled from the same sources as the native Leap 15.5 packages.
Moroeover, the 15.4 DUD contains a [shell script](update.pre), which
is run by the installer before performing the actual installation. The
script parses the NBFT, brings up the NBFT interface(s), and
connects to the NVMeoF subsystems.

[^dud]: See https://github.com/openSUSE/mkdud/blob/master/HOWTO.md
