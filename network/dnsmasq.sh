#! /bin/bash
export LC_ALL=C
: "${V:=}"
echo $0: V=$V N=$NVME_USE_OVS
# trace the script with V=2
[ "$V" != 2 ] || set -x

MYDIR=${0%/*}

. "$MYDIR/defaults.sh"
. "$MYDIR/functions.sh"

CLEANUP_SCRIPT="$PWD/network/cleanup-dnsmasq.sh"
CLEANUP=':'

dnsmasq_net() {
    local IFACE=$1 IP4_SUBNET=$2 IP4_MASK=$3
    local IP4_GATEWAY=${4:+$IP4_SUBNET$4}
    local IP6_PREFIX=$5 ROOT_SERVER=$6
    local RA_TTL=0

    # No routing diff between IPv4 and IPv6
    [ ! "$IP4_GATEWAY" ] || RA_TTL=1800
    cat <<EOF

interface=$IFACE
#local=/$IFACE/
domain=$IFACE,${IP4_SUBNET}0/$IP4_MASK,local
dhcp-host=$SERVER_NAME,${IP4_SUBNET}10,set:server,set:${IFACE}_4,$DHCP_LEASETIME

dhcp-range=set:${IFACE}_4,${IP4_SUBNET}129,${IP4_SUBNET}254,$DHCP_LEASETIME
dhcp-option=tag:${IFACE}_4,option:router${IP4_GATEWAY:+,$IP4_GATEWAY}
dhcp-option=tag:${IFACE}_4,option:dns-server,${IP4_SUBNET}1
dhcp-option=tag:${IFACE}_4,option:root-path,"nvme+tcp://${ROOT_SERVER:-$SERVER_NAME.$IFACE}:4420/$NQN//"

domain=$IFACE,${IP6_PREFIX}0/64,local
dhcp-host=$SERVER_NAME,[${IP6_PREFIX}10],set:server,set:${IFACE}_6,64,$DHCP_LEASETIME
dhcp-option=tag:${IFACE}_6,option6:dns-server,[${IP6_PREFIX}1]
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
dhcp-fqdn
domain=nvmeof
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
    push_cleanup '! read -r pid < "$DNSMASQ_DIR/dnsmasq-nvmeof.pid" || kill \$pid'
}

[[ -f "$CLEANUP_SCRIPT" ]] && exit 0
[ "$UID" -eq 0 ] || exec sudo "$0"

trap 'echo $0: line ${LINENO}: ERROR in \"$BASH_COMMAND\" >&2; exit 1' ERR
trap 'trap - ERR; echo "=== $0: cleaning up ===" >&2; eval "$CLEANUP"' 0
set -E

DO_OVS=
if [ "$NVME_USE_OVS" = 1 ]; then
    DO_OVS=yes
fi

include_conf_file network.conf

setup_dnsmasq
write_cleanup_script
trap - 0

exit 0
