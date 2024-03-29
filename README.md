# NVMe-of/TCP Boot with openSUSE Virtual Machines

## DISCLAIMER

These instructions have been created with diligence and
are provided in the hope that they will be useful, but **without guarantee of
any kind**. **Use at you own risk.**

## Note for Developers

The instructions below are based on various high level tools such as
**vagrant** and **ansible**, and driven by shell scripts and Makefiles.
This is designed to be flexible and relatively easy to set up, but it
naturally hides a lot of the details that go on behind the scenes.

If you want to understand the setup in more detail, please check the [Basic
walkthrough for developers](BASIC.md).

# Full Proof-of-Concept

## Quick Start for the Impatient

 * Check the [Prerequisites](#prerequisites).
 * Run **make help-rootless** and apply the [suggested settings](#enabling-rootless-operation).
 * Run **make server-up**.
 * Run **make AUTOINST=1 inst**, hit ESC quickly after VM startup.
 * Open Boot Manager and start `EFI Internal Shell`, let `startup.nsh`
   run. The boot menu will be displayed.
 * Open the boot manager again and watch out for an "NVMe" entry. If it
   doesn't exist, something went wrong, see below.
 * Reset the VM from the EFI Menu, it will reboot.
 * Select the DVD as boot device. The Installation menu
   will be displayed.
 * Edit the `Installation` entry, and add `console=ttyS0` to the kernel
   command line.
 * Start the installation.
 * After installation, the installed VM will boot from NVMe-oF. 
   The root password is "timberland".

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

While most of this Proof of Concept can be run rootless, some commands require
superuser priviliges, in particular network setup. Your user ID should have
permissions to run virtual machines both under plain qemu[^qemu_ovs] and under
libvirt. On most modern Linux distributions, this is granted by
adding the user to the groups `qemu` (or `kvm`) and `libvirt`, respectively.

[^qemu_ovs]: qemu will only be run under your user ID if no OpenVSwitch bridge
	is used, because bringing up openvswitch interfaces doesn't work with
	rootless qemu.

Thr command **make help-rootless** prints configuration hints
to enable passwordless execution for those commands
that need root permissions.
The output looks like this, with some variables substituted to
match your environment:

    ###  User joe must be able control qemu and libvirt
    Usually that means joe should be member of the groups "qemu" and "libvirt"
    
    ### Recommended sudoers configuration (add with visudo):
    User_Alias NVME_USERS = joe
    Host_Alias NVME_HOSTS = workstation
    Cmd_Alias NVME_CMDS = /home/joe/nvme-poc/qemu.sh ""
    Cmd_Alias NVME_NET = /home/joe/nvme-poc/network/setup.sh "", /home/joe/nvme-poc/network/cleanup.sh ""
    Defaults!NVME_CMDS env_keep += "VM_NAME VM_UUID VM_OVMF_IMG VM_BRIDGE VM_ISO VM_DUD VM_VGA_FLAGS V"
    Defaults!NVME_NET env_keep += "NVME_USE_OVS V"
    NVME_USERS NVME_HOSTS=(root) NOPASSWD: NVME_CMDS
    NVME_USERS NVME_HOSTS=(root) NOPASSWD: NVME_NET
    ### End of sudoers config ###
    
    ### /etc/qemu/bridge.conf configuration
    allow br_nvme

Review these suggestions, and apply them as you see fit.

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

    nvme discover -t tcp -a 192.168.49.10  -s 4420 -q "nqn.2014-08.org.nvmexpress:uuid:$UUID"

where UUID has been printed by the previous command, or can be found in the
file `uuid-$(VM_NAME).mk`[^hostnqn], where `VM_NAME` is set in `vm-config.mk`
and defaults to `leap`.

[^hostnqn]: Without the `-q` argument, `nvme discover` will print no
    subsystem, because ACLs on the server restrict access.

## Installing a Client Virtual Machine

**Important: kill a hanging qemu VM with `Ctrl-b x`.**[^ctrlb]

[^ctrlb]: By default, this PoC uses `Ctrl-b x` rather than qemu's default
    `Ctrl-a x`, in order to be able to run the PoC under **screen**.

The settings for the client are in `vm-config.mk`. Leaving the defaults as-is
should work for your first installation. You can change the settings later.

The PoC uses openSUSE Leap or SUSE Linux Enterprise (SLE)
(`BASE_DIST` in `vm-config.mk`).
Versions 15.4 and 15.5 are supported (`VERSION` in
`vm-config.mk`). If you have an installation medium (DVD) for the configured
openSUSE distribution around, copy or link it to `install.iso` in the top directory.
Otherwise, the next command will download the image from the internet[^iso].

[^iso]: The automatic download works for openSUSE leap only. For SLE, you need
    to obtain an iso image from the [SUSE download site](https://www.suse.com/download/sles/
	and create a symbolic link in the top directory pointing to this image.
	For SLE15-SP5, the name of the symbolic link should be
	`SLE-15-SP5-Full-x86_64-Media1.iso`.

The following command will download and build all necessary artifacts and start the VM.
Most importantly, it will build a small EFI disk with the `NvmeOfCli.efi`
executable and a `startup.nsh` script. This disk must be booted to set the
NVMe-oF boot attempt variables. Run 

    make inst

### First-time boot

**As soon as the VM starts, hit the `ESC` key**. If you miss it and PXE boot
starts, kill the VM with `Ctrl-b x` and try again. In the EFI main menu,
select `Boot Maintenance Manager → Boot Options` and disable the PXE boot
options. Back in the main EFI menu, select `Boot Manager → EFI Internal
Shell`. Don't interrupt and let the shell execute `startup.nsh`. 
Back in the main menu, **reset the VM**. See [What happened
here?](#what-happened-here) for an explanation of this step.

### Controlling the NVMe-oF setup

_(This step can be skipped)_. Hit `ESC` again during boot. If you're dropped
into the UEFI shell, type `exit`. In the UEFI main menu, enter the `Boot
Manager`. Verify that an NVMe-oF device is now offered a boot option. If this
is not the case, you'll need to troubleshoot your network and NVMe-oF
configuration. Select the first DVD-ROM in the boot manager to start the
installation.

### Installation

Wait until you see the boot menu from the openSUSE DVD (you my have to type
`t` first to display the menu on serial console). Move cursor to
`Installation`, type `e` to edit the line, and add `console=ttyS0` on the line
starting with `linux`[^vga]. Type `Ctrl-x` to start the installation.

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
manual` and add IPv6 address and gateway under `Advanced Configuration`.

Alternatively, this can be configured in the EFI shell.
The most reliable way to bring up an NVMeoF boot with IPv6 is as follows
(assuming the standard bridge with subnet `fddf:d:f:49::` is in use):

    rm vm/$VM_NAME-vars.fd    # VM_NAME from config.mk
    make qemu
	# hit ESC, disable PXE boot options 
	# boot EFI shell, hit ESC (*do not* run startup.nsh)
	# in efi shell, use ifconfig6 like above:
	ifconfig6 -s eth0 man host fddf:d:f:49::50/64 gw fddf:d:f:49::1
	# or for DHCP/SLAAC: ifconfig6 -s eth0 auto
	reset   # or ctrl-b x for poweroff
	# hit ESC again when the VM reboots
	# boot EFI shell and run startup.nsh this time

Note that running `startup.nsh` and reading the `CONFIG` file is still 
necessary for configuring NVMe-oF target parameters.

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

#### Using a test release of the OVMF firmware

By default, the latest released OVMF firmware from the [Timberland EDK2 GitHub
repository](https://github.com/timberland-sig/edk2/actions) will be downloaded
and used. The Timberland project uses **GitHub Actions** to build firmware
images automatically for new pull requests. These images can be downloaded
from the [actions page](https://github.com/timberland-sig/edk2/actions). Click
on the workflow run you're interested in, and on the workflow page, click on
"artifact". A file called `artifact.zip` will be downloaded. It contains a
file `timberland-ovmf.zip`. Copy this file into your working directory and run

    make OVMF
	make vars-clean
	make vars

This will create the images for UEFI code and variables under
`ovmf/OVMF_CODE.fd` and `ovmf/OVMF_VARS.fd`, respectively, and create a copy
of the variable store that's usable for your virtual machine.

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

### Network settings

Most of the time, failure to boot from NVMe is caused by network setup issues.

* Check the status of the bridges and interfaces. If in doubt, restart the
  virtual networks using

        make net-down
		make server-up

* Check firewall settings on the VM host; at the very least, DHCPv4/v6 queries
  need to be received by the dnsmasq daemon running on the host.

* Check the status of the NVMe target VM. You can enter the VM by changing to
  the `nvmet-server` subdirectory and running `vagrant ssh`. Once in the VM,
  you can run `sudo` to investigate the status and apply fixes. Verify that
  all configured interfaces of the server VM are up and have the expected IP
  addresses (see [Setting up the environment](#setting-up-the-environment)),
  and that the VM host can be pinged through any of them. By default, all IP
  addresses of the NVMet server exept the address of `eth0` will end with
  `.10` for IPv4 or `::10` for IPv6. Also run `nvmetcli ls` to verify the
  volumes exported by the server.

### Client settings

Examine the NVMe-oF configuration file `efidisk/Config` and make sure the 
settings match the configured bridges and the subsystems exported by the server.

### Debugging

On the VM host, the output of **dnsmasq** can be helpful to see if the server
and/or the client successfully retrieve IP addresses. It's
recommended to use a DHCP setup for the client initially, because otherwise
this debugging method won't be available.

Use **tcpdump** or similar tools on the VM host and / or on the NVMe target to
see whether the client tries to connect. The system log on the NVMe target
will log both successful and unsuccessful NVMe connection attempts.

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

### openSUSE Leap and SUSE Linux Enterprise Server (SLE)

openSUSE Leap 15.5 and SLE 15-SP5 have native support for installing on
NVMe-oF/TCP in their installation programs (`linuxrc` and `YaST`). Presence of
an NBFT table is automatically detected.

On openSUSE Leap 15.4 and SLE15-SP4, the driver update disk (DUD) concept[^dud] is leveraged
to install updated packages for **nvme-cli**, **dracut** and their
dependencies. These packages are not official 15.4 packages, but they
are compiled from the same sources as the native 15.5 packages.
Moroeover, the 15.4 DUD contains a [shell script](update.pre), which
is run by the installer before performing the actual installation. The
script parses the NBFT, brings up the NBFT interface(s), and
connects to the NVMeoF subsystems.

[^dud]: See https://github.com/openSUSE/mkdud/blob/master/HOWTO.md
