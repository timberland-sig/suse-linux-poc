#! /bin/bash
trap 'echo error in $BASH_COMMAND >&2; exit 1' ERR
: "${V:=}"
# trace the script with V=2
[ "$V" != 2 ] || set -x

MYDIR=$(realpath $(dirname "$0"))
LV_DIR=$MYDIR/libvirt

: "${VM_NAME:=nbft}"
: "${VM_UUID=$(uuidgen)}"
: "${NAME_PREFIX:=}"

TMPD=$(mktemp -d /tmp/nvmepoc.XXXXXX)
trap 'rm -rf $TMPD' 0

libvirt_network_name() {
    local -a LV_NETS net
    mapfile -t LV_NETS < <(virsh net-list --name)
    for net in  ${LV_NETS[@]}; do
	[[ "$net" ]] || continue
	virsh net-dumpxml "$net" >"$TMPD/net-$net.xml"
	[[ $(xsltproc --stringparam bridge "$1" "$LV_DIR/network-name.xslt" "$TMPD/net-$net.xml") \
	       != yes ]] || {
	    echo "$net"
	    return 0
	}
    done
    return 1
}

LV_NET=$(libvirt_network_name "$VM_BRIDGE")
LV_PG=

: "${BASE:=$MYDIR/ovmf}"
: "${OVMF_CODE:=$BASE/OVMF_CODE.fd}"
: "${OVMF_VARS:=$BASE/OVMF_VARS.fd}"
: "${MAC0:=$(echo "$VM_UUID" | sed -E 's/.*(..)(..)(..)/52:54:00:\1:\2:\3/')}"

[[ -f $OVMF_CODE ]]
[[ -f $OVMF_VARS ]]
[[ -f $MYDIR/efidisk.img ]]

VARS="$MYDIR/vm/$VM_NAME-vars.bin"
# initialize UEFI vars pflash
[ -f "$VARS" ] || {
    mkdir -p "$(dirname "$VARS")"
    cp "$OVMF_VARS" "$VARS"
}

xsltproc \
    --stringparam name "$NAME_PREFIX$VM_NAME" \
    --stringparam uuid "$VM_UUID" \
    --stringparam ovmf_code "$OVMF_CODE" \
    --stringparam ovmf_vars "$VARS" \
    --stringparam network "$LV_NET" \
    --stringparam portgroup "$LV_PG" \
    --stringparam mac_address "$MAC0" \
    --stringparam iso "${VM_ISO:+$MYDIR/$VM_ISO}" \
    --stringparam dud "${VM_DUD:+$MYDIR/$VM_DUD}" \
    --stringparam efidisk "$MYDIR/efidisk.img" \
    "$LV_DIR/vm.xslt" "$LV_DIR/vm.xml"
