#! /bin/bash
# If this script must be run as root, configuration
# must be done via the environment. Set env_keep in SUDOERS.
# root is required for openvswitch, as the qemu bridge helper doesn't support OVS
#
# Sample sudoers content:
#
# User_Alias NVME_USERS = joe
# Host_Alias NVME_HOSTS = vmhost
# Cmd_Alias NVME_CMDS = /home/joe/nbft/qemu.sh
# Defaults!NVME_CMDS env_keep += "VM_NAME VM_UUID VM_BRIDGE VM_ISO VM_DUD VM_VGA_FLAGS"
# NVME_USERS NVME_HOSTS=(root) NOPASSWD: NVME_CMDS

trap 'echo error in $BASH_COMMAND >&2; exit 1' ERR

## VM_xyz environment variables are normally passed from Makefile

# Setting defaults here in order to be able to run the script standalone

: "${V:=}"
# trace the script with V=2
[ "$V" != 2 ] || set -x

: "${VM_NAME:=nbft}"
: "${VM_UUID=$(uuidgen)}"
: "${VM_NETWORK_TYPE:=ovs}" # "ovs" or "bridge"

[ "$VM_NETWORK_TYPE" = bridge ] || [ "$UID" = 0 ] || exec sudo "$0"
: "${VM_VGA_FLAGS:=-vga none -display none}"

include_conf_file() {
    local _user _flags _perm

    [ -f "$1" ] || return 0

    _user=$(stat -c %U "$1")
    _perm=0$(stat -c %a "$1")
    if [ "$_user" = "$SUDO_USER" ] || [ "$_user" = "$USER" ] && \
	   [ $(( $_perm & 022)) -eq 0 ]; then
	echo === importing settings from "$1" >&2
	_flags="$(set +o)"
	set -x
	.  "./$1"
	set +x
	eval "$_flags"
    else
	echo === "$1" exists, but has unsafe permissions == >&2
    fi
}

include_conf_file "qemu.conf"
include_conf_file "qemu-${VM_NAME}.conf"

# Logging - set nonempty to enable
: "${QEMU_LOGGING:=}"

# Uncomment these to write log files
QEMU_OVMF_LOG="${QEMU_LOGGING:+/tmp/ovmf-"$VM_NAME".log}"
QEMU_SERIAL_LOG="${QEMU_LOGGING:+/tmp/serial-"$VM_NAME".log}"

## Debugging

# Use -s to enable attaching gdb
# to capture network traffic:
# -object filter-dump,id=dump0,netdev=n0,file=/tmp/nvme.pcap"
: "${QEMU_DBG_FLAGS:=}"
# Use Ctrl-b instead of Ctrl-a as escape char
: "${QEMU_ESCAPE_CHAR:=2}"


: "${QEMU:=qemu-system-x86_64}"
# See https://github.com/timberland-sig/edk2/issues/2 for "-cpu host"
: "${QEMU_BASE_FLAGS=-M q35 -m 1G -accel kvm -cpu host -uuid "$VM_UUID" -boot menu=on,splash-time=2000}"

: "${BASE:=./ovmf}"
: "${OVMF_CODE:=$BASE/OVMF_CODE.fd}"
: "${OVMF_VARS:=$BASE/OVMF_VARS.fd}"
: "${MAC0:=$(echo "$VM_UUID" | sed -E 's/.*(..)(..)(..)/52:54:00:\1:\2:\3/')}"

VARS="$PWD/vm/$VM_NAME-vars.bin"

# initialize UEFI vars pflash
[ -f "$VARS" ] || {
    mkdir -p "$(dirname "$VARS")"
    cp -v "$OVMF_VARS" "$VARS"
    [ ! $SUDO_USER ] || chown "$SUDO_USER" "$VARS"
}

if [ -f ./efidisk.img ] && [ ! ./efidisk.img -ot ./efidisk/Config ]; then
    QEMU_IMG_FLAGS="\
-drive file=./efidisk.img,media=disk"
else
    QEMU_IMG_FLAGS="\
-drive format=raw,file=fat:rw:./efidisk"
fi

QEMU_INST_FLAGS="\
${VM_ISO:+-drive file="$VM_ISO",media=cdrom,index=2 \
${VM_DUD:+-drive file="$VM_DUD",media=cdrom,index=3}} \
"

QEMU_VGA_FLAGS="$VM_VGA_FLAGS"

QEMU_SERIAL_FLAGS="\
-chardev stdio,mux=on,signal=off,id=char0${QEMU_SERIAL_LOG:+,logfile="$QEMU_SERIAL_LOG"} \
-serial chardev:char0 \
-mon chardev=char0,mode=readline \
-echr $QEMU_ESCAPE_CHAR"

QEMU_OVMF_FLAGS="\
-drive if=pflash,format=raw,readonly=on,file=$OVMF_CODE \
-drive if=pflash,format=raw,file=$VARS \
${QEMU_OVMF_LOG:+-debugcon file:"$QEMU_OVMF_LOG" -global isa-debugcon.iobase=0x402} \
"

QEMU_OTHER_FLAGS="\
-object rng-builtin,id=rng0 -device virtio-rng,rng=rng0"

case $VM_NETWORK_TYPE in
    bridge)
	: "${VM_BRIDGE:=br_nvme}"
	QEMU_NET_FLAGS="\
	-netdev bridge,id=n0,br=$VM_BRIDGE \
	-device virtio-net-pci,netdev=n0,mac=$MAC0"
	;;
    ovs)
	: "${VM_BRIDGE:=ovs_nvme}"
	QEMU_NET_FLAGS="\
	-netdev tap,id=n0,script=$PWD/ovs-ifup,downscript=$PWD/ovs-ifdown \
	-device virtio-net-pci,netdev=n0,mac=$MAC0"
	;;
esac

set -x
$QEMU \
    $QEMU_BASE_FLAGS \
    $QEMU_INST_FLAGS \
    $QEMU_VGA_FLAGS \
    $QEMU_SERIAL_FLAGS \
    $QEMU_OVMF_FLAGS \
    $QEMU_NET_FLAGS \
    $QEMU_IMG_FLAGS \
    $QEMU_OTHER_FLAGS \
    $QEMU_DBG_FLAGS
