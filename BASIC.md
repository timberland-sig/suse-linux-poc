# Basic Walkthrough for Developers

**Important:** This section is intended for **developers and advanced users** who want to
understand how the setup is built from ground up. If this doesn't apply
to you, please skip this section and go directly to the [Full Proof-of-Concept](README.md)
instead.

**This entire section assumes that you work with root rights.**

## DISCLAIMER

These instructions have been created with diligence and
are provided in the hope that they will be useful, but **without guarantee of
any kind**. **Use at you own risk.** It is **strongly discouraged** to run the
commands  below on production systems.

## System Requirements

Install QEMU/KVM, the QEMU bridge helper, nvme-cli, and curl. 
Under openSUSE, you would do it like this:

    zypper install qemu-kvm qemu-tools nvme-cli curl

## Preparations

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

## Setting up the Network Bridge

Create the bridge device, configure an IP address, and allow qemu
to connect to it. If you are running a firewall, add this interface 
to a zone that permits all traffic. The example below shows how to do this
with firewalld.

    ip link add "$BRIDGE" type bridge stp_state 0
    ip link set "$BRIDGE" up
    ip addr add "$NET.1/24" dev "$BRIDGE"
    echo "allow $BRIDGE" >>/etc/qemu/bridge.conf
    firewall-cmd --zone trusted --add-interface="$BRIDGE"

Change into your working directory and create an empty disk image.

    mkdir -p "$DIR"
    cd "$DIR"
    truncate -s 20G "$DISK"

## Configuring the NVMe Target

Load kernel modules for the NMVe target, create the NQN, and link it to the
disk you just created. Allow any host to connect[^simple].

    modprobe nvmet nvmet-tcp
    cd /sys/kernel/config/nvmet/subsystems
    mkdir "$NQN"
    cd "$NQN"
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
    echo "$NET.1" > addr_traddr
    echo 4420 > addr_trsvcid
    ln -s "/sys/kernel/config/nvmet/subsystems/$NQN" subsystems

Your NVMe target is now operational. You can test it like this:

    modprobe nvme-fabrics
    nvme discover -t tcp -a "$NET.1" -s 4420

This command should display two entries, one of the referencing the NQN
defined above.

## Downloading the NVMe-oF Enabled OVMF Firmware

Change back to your working directory, download and unpack the NVMe-oF enabled
EDK2 firmware, and make a copy of the UEFI variable store[^ovmf_url]:

    cd "$DIR"
    curl -s -L -o ovmf.zip https://github.com/timberland-sig/edk2/releases/download/release-9e63dc0/timberland-ovmf-release-9e63dc0.zip
    unzip ovmf.zip
	cp OVMF_VARS.fd vm_vars.fd

The ZIP archive contains 4 files: `OVMF_CODE.fd` (the actual firmware image),
`OVMF_VARS.fd` (an empty UEFI non-volatile variable store),
`NvmeOfCli.efi` (the EFI utilitiy used to load an NVMe-oF boot attempt
configuration into UEFI variables), and `VConfig.efi`, which you don't need.
Move the `NvmeOfCli.efi` tool into a separate directory.

    mkdir efi
    mv NvmeOfCli.efi efi
    
[^ovmf_url]: You can obtain the URL of the latest release with the command
	`curl -s https://api.github.com/repos/timberland-sig/edk2/releases/latest |  grep browser_download_url`. 

## Creating an NVMe-oF Boot Attempt Configuration

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

## Starting the Test Virtual Machine

Now it's time to run your VM. To simplify matters, define an alias with the
commonly used options[^vga]:

    alias qq="\
	qemu-system-x86_64 -M q35 -m 1G -accel kvm -cpu host \
      -nographic -device virtio-rng -boot menu=on,splash-time=2000 \
      -drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.fd \
      -drive if=pflash,format=raw,file=vm_vars.fd \
      -netdev bridge,id=n0,br=\"$BRIDGE\" -device virtio-net-pci,netdev=n0,mac=\"$MAC\""

Run this VM with the `efi` directory as a small pseudo-disk.
**Hit `ESC` quickly after typing the following command, to skip PXE boot.
If you miss and PXE starts, quit the VM by typing `Ctrl-a x` and try again.**

    qq -drive format=raw,file=fat:rw:./efi

In the main menu, select `Boot Manager`, and boot `EFI Internal Shell`. Do not
interrupt, `startup.nsh` will run, and the main menu will be shown again.
Shut down the VM using `Ctrl-a x`.

### What happened here?

The `startup.nsh` file is auto-executed by the EFI shell. It runs
`NvmeOfCli.efi`, which loads the configuration from the `config` file and
stores it in a non-volatile EFI variable. On the subsequent boot, the EFI NVMe-oF/TCP driver will find
this variable, set up the network as configured, and attempt to connect to the
target subsystem. If successful, it will provide a boot menu entry and will
store the boot parameters in the `NBFT` ACPI table, from where the operating
system will be able to retrieve it later.

## Installing openSUSE Leap

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

## Examining the Booted System

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
proof-of-concept setup instead, as described in [the Proof of Concept](README.md).
