#! /bin/bash
export LC_ALL=C
: "${V:=}"
# trace the script with V=2
[ "$V" != 2 ] || set -x

MYDIR=${0%/*}

. "$MYDIR/defaults.sh"
. "$MYDIR/functions.sh"

CLEANUP_SCRIPT="$PWD/network/cleanup.sh"
CLEANUP=':'

# Used to generate the ansible input file.
# We have this here in order to just need to calculate the networks
# in one place
print_networks() {
    local i
    local yaml="\
  - $(ovs_ipv4 0)0/$OVS_MASK\\
  - $(ovs_ipv6 0)0/$OVS_PREFIX6"

    for i in $(seq 1 "$NVME_N_VLANS"); do
	yaml="\
  - $(ovs_ipv4 "$i")0/$OVS_MASK\\
  - $(ovs_ipv6 "$i")0/$OVS_PREFIX6\\
$yaml"
    done

    for i in $(seq 1 "$NVME_N_BRIDGES"); do
	yaml="\
  - $(br_ipv4 "$i")0/$BR_MASK\\
  - $(br_ipv6 "$i")0/$BR_PREFIX6\\
$yaml"
    done
    sed "/^nvmet_networks:/a\\$yaml"
}

setup_bridge() {
    local active bridge br_net br_net6
    local br_idx=$1

    case $br_idx in
	[1-9]) ;;
	*) echo "=== $0: invalid bridge index \"$br_idx\" ===" >&2
	   return 1
	   ;;
    esac
    bridge="$BRIDGE$br_idx"
    br_net=$(br_ipv4 "$br_idx")
    br_net6=$(br_ipv6 "$br_idx")

    active=$(virsh net-info "$bridge" 2>/dev/null | awk '/^Active/{ print $2; }')
    case $active in
	yes)
	    echo "=== $0: libvirt bridge $bridge  is already active ===" >&2
	    return 0;
	    ;;
	no)
	    echo "=== $0: starting libvirt bridge $bridge ===" >&2
	    virsh -q net-start "$bridge"
	    push_cleanup 'virsh -q net-destroy '"$bridge"
	    return 0;
    esac
    echo "=== $0: creating bridge $bridge with IP range ${br_net}0/$BR_MASK and $br_net6/$BR_PREFIX6 ===" >&2

    ip link add "$bridge" type bridge stp_state 0
    push_cleanup "ip link del '$bridge' type bridge"
    ip link set "$bridge" up
    push_cleanup "ip link set '$bridge' down"
    ip addr add "${br_net}1/$BR_MASK" dev "$bridge"
    push_cleanup "ip addr flush '$bridge'"
    ip -6 addr add "${br_net6}1/$BR_PREFIX6" dev "$bridge"
    push_cleanup "ip -6 addr flush '$bridge'"
    firewall-cmd -q --add-interface="$bridge" --zone="$ZONE"
    push_cleanup "firewall-cmd -q --remove-interface='$bridge' --zone='$ZONE'"
    virsh -q net-define <(cat <<EOF
<network>
  <name>$bridge</name>
  <forward mode="bridge"/>
  <bridge name="$bridge"/>
</network>
EOF
)
    push_cleanup "virsh -q net-undefine '$bridge'"
    virsh -q net-start "$bridge"
    push_cleanup "virsh -q net-destroy '$bridge'"
}

setup_ovs_vlan() {
    local ovs_bridge=$1
    local vlan_id=$2
    local port="nvme$vlan_id"

    ovs-vsctl add-port "$ovs_bridge" "$port" tag="$vlan_id" -- \
	      set Interface "$port" type=internal
    push_cleanup "ovs-vsctl del-port '$ovs_bridge' '$port'"

    ip addr add "$(ovs_ipv4 "$vlan_id")1/$OVS_MASK" dev "$port"
    ip addr add "$(ovs_ipv6 "$vlan_id")1/$OVS_PREFIX6" dev "$port"
    push_cleanup "ip addr flush dev '$port'"

    ip link set dev "$port" up
    push_cleanup "ip link set dev '$port' down"

    firewall-cmd -q --add-interface="$port" --zone="$ZONE"
    push_cleanup "firewall-cmd -q --remove-interface='$PORT' --zone='$ZONE'"
}

ovs_vlan_xml() {
    local id

    for id in $(seq 1 "$NVME_N_VLANS"); do
	echo "\
<portgroup name='pg$id'>
  <vlan>
    <tag id='$id'/>
  </vlan>
</portgroup>"
    done
}

ovs_trunk_xml() {
    local id

    for id in $(seq 1 "$NVME_N_VLANS"); do
	echo "<tag id='$id'/>"
    done
}

setup_ovs() {
    local active brdev
    local vlan_id

    [[ "$DO_OVS" ]] || return 0

    if ! ovs-vsctl br-exists "$OVS_BRIDGE"; then
	ovs-vsctl add-br "$OVS_BRIDGE"
	push_cleanup 'ovs-vsctl del-br "$OVS_BRIDGE"'
    fi
    ip addr add "$(ovs_ipv4 0)1/$OVS_MASK" dev "$OVS_BRIDGE"
    ip addr add "$(ovs_ipv6 0)1/$OVS_PREFIX6" dev "$OVS_BRIDGE"
    push_cleanup 'ip addr flush dev "$OVS_BRIDGE"'
    ip link set dev "$OVS_BRIDGE" up
    push_cleanup 'ip link set dev "$OVS_BRIDGE" down'
    firewall-cmd -q --add-interface="$OVS_BRIDGE" --zone="$ZONE"
    push_cleanup 'firewall-cmd -q --remove-interface="$OVS_BRIDGE" --zone="$ZONE"'

    for vlan_id in $(seq 1 "$NVME_N_VLANS"); do
	setup_ovs_vlan "$OVS_BRIDGE" "$vlan_id"
    done

    active=$(virsh net-info "$OVS_BRIDGE" 2>/dev/null | awk '/^Active/{ print $2; }')
    if [ "$active" ]; then
	brdev=$(xsltproc <(cat <<\EOF
<stylesheet version="1.0" xmlns="http://www.w3.org/1999/XSL/Transform">
  <output method="text" omit-xml-declaration="yes"/>
  <template match="@*|node()"><apply-templates select="@*|node()"/></template>
  <template match="/network/bridge"><value-of select="@name"/></template>
</stylesheet>
EOF
) <(virsh net-dumpxml "$OVS_BRIDGE") 2>/dev/null)
	# the libvirt network exists - make sure it maps to the correct bridge
	[[ "$brdev" = "$OVS_BRIDGE" ]]
    else
	echo "=== $0: creating OVS bridge $OVS_BRIDGE with VLANs $(seq -s " " 1 "$NVME_N_VLANS") ===" >&2
	virsh -q net-define <(cat <<EOF
<network>
  <name>$OVS_BRIDGE</name>
  <forward mode='bridge'/>
  <bridge name='$OVS_BRIDGE'/>
  <virtualport type='openvswitch'/>
  <portgroup name='trunk' default='yes'>
    <vlan trunk='yes'>
      $(ovs_trunk_xml)
    </vlan>
  </portgroup>
  <portgroup name='pg0'/>
  $(ovs_vlan_xml)
</network>
EOF
)
	push_cleanup 'virsh -q net-undefine "$OVS_BRIDGE"'
    fi
    if [[ "$active" != yes ]]; then
	echo "=== $0: starting OVS bridge $OVS_BRIDGE ===" >&2
	virsh -q net-start "$OVS_BRIDGE"
	push_cleanup 'virsh -q net-destroy "$OVS_BRIDGE"'
    fi
    sleep 1
}

dnsmasq_net() {
    local IFACE=$1 IP4_SUBNET=$2 IP4_MASK=$3
    local IP4_GATEWAY=${4:+$IP4_SUBNET$4}
    local IP6_PREFIX=$5 ROOT_SERVER=$6
    local RA_TTL=0

    # No routing diff between IPv4 and IPv6
    [ ! "$IP4_GATEWAY" ] || RA_TTL=1800
    cat <<EOF

interface=$IFACE
local=/$IFACE/
domain=$IFACE,${IP4_SUBNET}0/$IP4_MASK
dhcp-host=$SERVER_NAME,${IP4_SUBNET}10,set:server,set:${IFACE}_4,$DHCP_LEASETIME

dhcp-range=set:${IFACE}_4,${IP4_SUBNET}129,${IP4_SUBNET}254,$DHCP_LEASETIME
dhcp-option=tag:${IFACE}_4,option:router${IP4_GATEWAY:+,$IP4_GATEWAY}
dhcp-option=tag:${IFACE}_4,option:root-path,"nvme+tcp://${ROOT_SERVER:-$SERVER_NAME.$IFACE}:4420/$NQN//"

dhcp-host=$SERVER_NAME,[${IP6_PREFIX}10],set:server,set:${IFACE}_6,64,$DHCP_LEASETIME
dhcp-range=set:${IFACE}_6,${IP6_PREFIX}80${IP6_END:+,${IP6_PREFIX}${IP6_END}}${IP6_RANGEOPT},64,$DHCP_LEASETIME
ra-param=$IFACE,$RA_INTERVAL,$RA_TTL

EOF
}

setup_dnsmasq() {
    # IPv6: don't advertize a route, just the prefix
    local RA_TTL=0
    local IP6_END=ff IP6_RANGEOPT= ENABLE_RA=
    local br vl

    mkdir -p "$DNSMASQ_DIR"
    push_cleanup 'rmdir --ignore-fail-on-non-empty "$DNSMASQ_DIR"'

    echo "=== $0: starting dnsmasq, config: $DNSMASQ_DIR/dnsmasq-nvmeof.conf ==="

    case $DHCP6_TYPE in
    slaac)
	    # RA A=1, M=0, O=0
	    IP6_END=
	    IP6_RANGEOPT=,slaac
	    ;;
    stateless)
	    # RA A=1, M=0, O=1
	    IP6_RANGEOPT=,ra-stateless
	    ;;
    dhcp+slaac)
	    # RA A=1, M=1, O=1
	    IP6_RANGEOPT=,slaac
	    ;;
    dhcp+ra)
	    # RA A=0, M=1, O=1
	    ENABLE_RA=enable-ra
	    ;;
    dhcp)
	    # DHCP, no RA
	    ;;
    *)
	    echo "ERROR: invalid DHCP6_TYPE=$DHCP6_TYPE" >&2
	    return 1
	    ;;
    esac

    [ ! "$BR_GATEWAY_SUFFIX" ] || RA_TTL=1800
    cat >"$DNSMASQ_DIR/dnsmasq-nvmeof.conf" <<EOF
strict-order
no-hosts
no-resolv
except-interface=lo
bind-dynamic
bogus-priv
domain-needed
dhcp-authoritative
leasefile-ro
dhcp-leasefile=/dev/null
$ENABLE_RA
$DNSMASQ_EXTRA_OPTS
EOF
    for br in $(seq 1 "$NVME_N_BRIDGES"); do
	dnsmasq_net "$BRIDGE$br" "$(br_ipv4 "$br")" "$BR_MASK" "$BR_GATEWAY_SUFFIX" \
		    "$(br_ipv6 "$br")" "$BR_RP_SERVER" \
		    >> "$DNSMASQ_DIR/dnsmasq-nvmeof.conf"
    done

    [ ! "$OVS_GATEWAY" ] || RA_TTL=1800
    [ ! "$DO_OVS" ] || {
	dnsmasq_net "$OVS_BRIDGE" "$(ovs_ipv4 0)" "$OVS_MASK" "$OVS0_GATEWAY" \
		    "$(ovs_ipv6 0)" "$OVS_RP_SERVER" >> "$DNSMASQ_DIR/dnsmasq-nvmeof.conf"
	for vl in $(seq 1 "$NVME_N_VLANS"); do
	    dnsmasq_net "nvme$vl" "$(ovs_ipv4 "$vl")" "$OVS_MASK" "$OVS_GATEWAY" \
			"$(ovs_ipv6 "$vl")" "$OVS_RP_SERVER" >> "$DNSMASQ_DIR/dnsmasq-nvmeof.conf"
	done
    }
    push_cleanup 'rm -f $DNSMASQ_DIR/dnsmasq-nvmeof.conf'

    [ "$V" != 2 ] || {
	echo "=== begin $DNSMASQ_DIR/dnsmasq-nvmeof.conf ==="
	grep -n . "$DNSMASQ_DIR/dnsmasq-nvmeof.conf"
	echo "=== end   $DNSMASQ_DIR/dnsmasq-nvmeof.conf ==="
    }

    dnsmasq --pid-file="$DNSMASQ_DIR/dnsmasq-nvmeof.pid" -C "$DNSMASQ_DIR/dnsmasq-nvmeof.conf"
    usleep 100000
    PID=$(cat $DNSMASQ_DIR/dnsmasq-nvmeof.pid)
    echo "=== dnsmasq PID: $PID" >&2
    push_cleanup "rm -f $DNSMASQ_DIR/dnsmasq-nvmeof.pid"
}

case $1 in
    networks)
	print_networks
	exit 0
	;;
    "")
	;;
    *)
	echo "$0: invalid parameter $1" >&2
	exit 1
	;;
esac

[ "$UID" -eq 0 ] || exec sudo "$0"

trap 'echo $0: line ${LINENO}: ERROR in \"$BASH_COMMAND\" >&2; exit 1' ERR
trap 'trap - ERR; echo "=== $0: cleaning up ===" >&2; eval "$CLEANUP"' 0
set -E

[[ -f "$CLEANUP_SCRIPT" ]] && exit 0
DO_OVS=
if [ "$NVME_USE_OVS" = 1 ]; then
    DO_OVS=yes
fi

[ ! "$DO_OVS" ] || command -v ovs-vsctl >/dev/null

include_conf_file network.conf

for br in $(seq 1 "$NVME_N_BRIDGES"); do
    setup_bridge "$br"
done
setup_ovs
setup_dnsmasq
[[ "$DO_OVS" != yes ]] || {
    "$MYDIR"/router.sh
    push_cleanup \
	"[ -x '$MYDIR'/cleanup-router.sh ] && '$MYDIR'/cleanup-router.sh"
}

write_cleanup_script
trap - 0

exit 0
