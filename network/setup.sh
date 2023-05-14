#! /bin/bash
: "${V:=}"
# trace the script with V=2
[ "$V" != 2 ] || set -x

# Set environment variables in "network.conf" to override the settings below
# Parameters for calculating IP address ranges
: "${ULA_PREFIX:=fddf:d:f}"
: "${IP4_PREFIX:=192.168}"
: "${OVS_VLAN_ID:=1}"
: "${SUBNET_BASE:=50}"
# This should match server.vm.hostname in nvmet/Vagrantfile
: "${SERVER_NAME:=vagrant-nvmet}"
# Set to a firewall zone that allows incoming dhcp (v4/v6) and dns
: "${ZONE:=libvirt}"
# IPv6 autoconfiguration methods
# values: slaac, stateless, dhcp+slaac, dhcp+ra, dhcp
# see below
: "${DHCP6_TYPE:=dhcp+ra}"
# Router advertisements
: "${RA_INTERVAL:=30}"
# Lease time (s)
: "${DHCP_LEASETIME:=300}"
: "${NQN:=nqn.2014-08.org.nvmexpress.discovery}"
# Use e.g. for root-path assignments or static IPs
: "${DNSMASQ_EXTRA_OPTS:=}"

: "${BRIDGE:=br_nvme}"
: "${BR_NET:=$IP4_PREFIX.$((SUBNET_BASE-1)).}"
: "${BR_MASK:=24}"
: "${BR_IPV6:=$ULA_PREFIX:$((SUBNET_BASE-1))::}"
: "${BR_PREFIX6:=64}"
# Set to gateway IP address (${BR_NET}1) to enable routing
: "${BR_GATEWAY:=}"

: "${OVS_BRIDGE:=ovs_nvme}"
: "${OVS0_NET:=$IP4_PREFIX.$SUBNET_BASE.}"
: "${OVS_NET:=$IP4_PREFIX.$((SUBNET_BASE+OVS_VLAN_ID)).}"
: "${OVS_MASK:=24}"
: "${OVS0_IPV6:=$ULA_PREFIX:$SUBNET_BASE::}"
: "${OVS_IPV6:=$ULA_PREFIX:$((SUBNET_BASE+OVS_VLAN_ID))::}"
: "${OVS0_PREFIX6:=64}"
: "${OVS_PREFIX6:=64}"
# Set to gateway IP address (${OVS_NET}1) to enable routing
: "${OVS0_GATEWAY:=}"
: "${OVS_GATEWAY:=}"

# Set this in network.conf to override the server name
# in the DHCP root-path option (e.g. for using the IP address of the server)
# the default is the server's FQDN
: "${BR_RP_SERVER:=}"
: "${OVS_RP_SERVER:=}"
: "${OVS0_RP_SERVER:=}"

# Directory where to store dnsmasq conf files
# location may depend on security settings (Apparmor)
: "${DNSMASQ_DIR:=/run/dnsmasq}"

export LC_ALL=C
CLEANUP_SCRIPT="$PWD/network/cleanup.sh"
CLEANUP='rm -f "$CLEANUP_SCRIPT"'
push_cleanup() {
    CLEANUP="$@
$CLEANUP"
}

# Used to generate the ansible input file.
# We have this here in order to just need to calculate the networks
# in one place
print_networks() {
    sed "/^nvme_networks:/a\\
  - ${BR_NET}0/$BR_MASK\\
  - ${OVS0_NET}0/$OVS_MASK\\
  - ${OVS_NET}0/$OVS_MASK\\
  - ${BR_IPV6}/$BR_PREFIX6\\
  - ${OVS0_IPV6}/$OVS_PREFIX6\\
  - ${OVS_IPV6}/$OVS_PREFIX6"
}

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

setup_bridge() {
    local active

    active=$(virsh net-info "$BRIDGE" 2>/dev/null | awk '/^Active/{ print $2; }')
    case $active in
	yes)
	    echo "=== $0: libvirt bridge $BRIDGE  is already active ===" >&2
	    return 0;
	    ;;
	no)
	    echo "=== $0: starting libvirt bridge $BRIDGE ===" >&2
	    virsh -q net-start "$BRIDGE"
	    push_cleanup 'virsh -q net-destroy "$BRIDGE"'
	    return 0;
    esac
    echo "=== $0: creating bridge $BRIDGE with IP range ${BR_NET}0/$BR_MASK and $BR_IPV6/$BR_PREFIX6 ===" >&2

    ip link add "$BRIDGE" type bridge stp_state 0
    push_cleanup 'ip link del "$BRIDGE" type bridge'
    ip link set "$BRIDGE" up
    push_cleanup 'ip link set "$BRIDGE" down'
    ip addr add "${BR_NET}1/$BR_MASK" dev "$BRIDGE"
    push_cleanup 'ip addr flush "$BRIDGE"'
    ip -6 addr add "${BR_IPV6}1/$BR_PREFIX6" dev "$BRIDGE"
    push_cleanup 'ip -6 addr flush "$BRIDGE"'
    firewall-cmd -q --add-interface="$BRIDGE" --zone="$ZONE"
    push_cleanup 'firewall-cmd -q --remove-interface="$BRIDGE" --zone="$ZONE"'
    virsh -q net-define <(cat <<EOF
<network>
  <name>$BRIDGE</name>
  <forward mode="bridge"/>
  <bridge name="$BRIDGE"/>
</network>
EOF
)
    push_cleanup 'virsh -q net-undefine "$BRIDGE"'
    virsh -q net-start "$BRIDGE"
    push_cleanup 'virsh -q net-destroy "$BRIDGE"'
}

setup_ovs() {
    local active brdev

    [[ "$DO_OVS" ]] || return 0
    PORT=nvme$OVS_VLAN_ID
    TAG=$PORT
    DOMAIN=$PORT

    if ! ovs-vsctl br-exists "$OVS_BRIDGE"; then
	ovs-vsctl add-br "$OVS_BRIDGE"
	push_cleanup 'ovs-vsctl del-br "$OVS_BRIDGE"'
    fi
    ip addr add "${OVS0_NET}1/$OVS_MASK" dev "$OVS_BRIDGE"
    ip addr add "${OVS0_IPV6}1/$OVS0_PREFIX6" dev "$OVS_BRIDGE"
    push_cleanup 'ip addr flush dev "$OVS_BRIDGE"'
    ip link set dev "$OVS_BRIDGE" up
    push_cleanup 'ip link set dev "$OVS_BRIDGE" down'
    ovs-vsctl add-port "$OVS_BRIDGE" "$PORT" tag="$OVS_VLAN_ID" -- set Interface "$PORT" type=internal
    push_cleanup 'ovs-vsctl del-port "$OVS_BRIDGE" "$PORT"'
    ip addr add "${OVS_NET}1/$OVS_MASK" dev "$PORT"
    ip addr add "${OVS_IPV6}1/$OVS_PREFIX6" dev "$PORT"
    push_cleanup 'ip addr flush dev "$PORT"'
    ip link set dev "$PORT" up
    push_cleanup 'ip link set dev "$PORT" down'
    firewall-cmd -q --add-interface="$PORT" --zone="$ZONE"
    push_cleanup 'firewall-cmd -q --remove-interface="$PORT" --zone="$ZONE"'

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
	echo "=== $0: creating OVS bridge $OVS_BRIDGE with vlan id $OVS_VLAN_ID on $PORT ===" >&2
	virsh -q net-define <(cat <<EOF
<network>
  <name>$OVS_BRIDGE</name>
  <forward mode='bridge'/>
  <bridge name='$OVS_BRIDGE'/>
  <virtualport type='openvswitch'/>
  <portgroup name='trunk' default='yes'>
    <vlan trunk='yes'>
      <tag id='$OVS_VLAN_ID'/>
    </vlan>
  </portgroup>
  <portgroup name='pg0'/>
  <portgroup name='pg$OVS_VLAN_ID'>
    <vlan>
      <tag id='$OVS_VLAN_ID'/>
    </vlan>
  </portgroup>
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
    local IFACE=$1 IP4_SUBNET=$2 IP4_MASK=$3 IP4_GATEWAY=$4
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

    [ ! "$BR_GATEWAY" ] || RA_TTL=1800
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
    dnsmasq_net "$BRIDGE" "$BR_NET" "$BR_MASK" "$BR_GATEWAY" \
		"$BR_IPV6" "$BR_RP_SERVER" >> "$DNSMASQ_DIR/dnsmasq-nvmeof.conf"

    [ ! "$OVS_GATEWAY" ] || RA_TTL=1800
    [ ! "$DO_OVS" ] || {
	dnsmasq_net "$OVS_BRIDGE" "$OVS0_NET" "$OVS_MASK" "$OVS0_GATEWAY" \
		    "$OVS0_IPV6" "$OVS0_RP_SERVER" >> "$DNSMASQ_DIR/dnsmasq-nvmeof.conf"
	dnsmasq_net "$PORT" "$OVS_NET" "$OVS_MASK" "$OVS_GATEWAY" \
		    "$OVS_IPV6" "$OVS_RP_SERVER" >> "$DNSMASQ_DIR/dnsmasq-nvmeof.conf"
    }
    push_cleanup 'rm -f $DNSMASQ_DIR/dnsmasq-nvmeof.conf'

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

trap 'echo $0: line ${LINENO}: ERROR in \"$BASH_COMMAND\" >&2; exit 1' ERR
trap 'trap - ERR; echo "=== $0: cleaning up ===" >&2; eval "$CLEANUP"' 0
set -E

[ "$UID" -eq 0 ] || {
    echo "=== $0: trying to run as root ===" >&2
    exec sudo "$0"
}

DO_OVS=
if [ "$NVME_USE_OVS" = 1 ]; then
    DO_OVS=yes
fi

[ ! "$DO_OVS" ] || command -v ovs-vsctl >/dev/null

include_conf_file network.conf

setup_bridge
setup_ovs
setup_dnsmasq

cat >"$CLEANUP_SCRIPT" <<EOF
#! /bin/bash
$([ "$V" != 2 ] || echo 'set -x')
[ \$UID -eq 0 ] || {
    echo "=== \$0: trying to run as root ===" >&2
    exec sudo "\$0"
}
export LC_ALL=C

! read -r pid < $DNSMASQ_DIR/dnsmasq-nvmeof.pid || kill \$pid
EOF
eval "echo \"$CLEANUP\"" >>"$CLEANUP_SCRIPT"
chmod a+x "$CLEANUP_SCRIPT"

trap - 0
echo "=== $0: to clean up, run $CLEANUP_SCRIPT ==="
exit 0
