#! /bin/bash
export LC_ALL=C
: "${V:=}"
# trace the script with V=2
[ "$V" != 2 ] || set -x
[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

MYDIR=${0%/*}

. "$MYDIR/defaults.sh"
. "$MYDIR/functions.sh"

CLEANUP_SCRIPT="$PWD/network/cleanup-router.sh"
CLEANUP=':'

add_router_veth() {
    local ns=$1 id=$2 ip4=$3 ip6=$4
    local intern=${ns//:/_}_${id}
    local tmp=__$intern
    local peer=vlan$id

    ip link add "$intern" type veth peer name "$tmp"
    push_cleanup "ip link del '$intern' || true"

    ip link set "$tmp" netns "$ns"
    ip netns exec "$ns" \
       ip link set "$tmp" name "$peer"
    push_cleanup "ip netns exec '$ns' ip link del '$peer'"

    ovs-vsctl add-port "$OVS_BRIDGE" "$intern" "tag=$id"
    push_cleanup "ovs-vsctl del-port '$OVS_BRIDGE' '$intern'"

    ip link set "$intern" up
    push_cleanup "ip link set '$intern' down"

    ip netns exec "$ns" \
       ip link set "$peer" up
    push_cleanup "ip netns exec '$ns' ip link set '$peer' down"

    ip netns exec "$ns" \
       ip addr add "$(ovs_ipv4 "$id")$ip4/$OVS_MASK" dev "$peer"
    ip netns exec "$ns" \
       ip addr add "$(ovs_ipv6 "$id")$ip6/$OVS_PREFIX6" dev "$peer"
    push_cleanup "ip netns exec '$ns' ip addr flush '$peer'"
}

add_router() {
    local pair=$1
    local id1 id2
    local name ip4 ip6

    id1=${pair%:*}
    id2=${pair#*:}

    [[ "$id1" ]]
    [[ "$id2" ]]
    [[ "$id1" -ge 0 ]]
    [[ "$id1" -le "$NVME_N_VLANS" ]]
    [[ "$id2" -ge 0 ]]
    [[ "$id2" -le "$NVME_N_VLANS" ]]
    [[ "$id1" -ne "$id2" ]]

    name="${NVME_ROUTER_NETNS}${id1}:${id2}"
    ip6="$(printf "9:%02x%02x" "${id1}" "${id2}")"
    ip4="$((IPv4_ROUTER_OFFSET + 8 * id1 + id2))"

    echo "$0: creating network namespace '$name' (.$ip4)"
    ip netns add "$name"
    push_cleanup "ip netns del '$name'"
    push_cleanup "ip netns pids '$name' | xargs -r kill"

    ip netns exec "$name" \
       sh -c 'echo 1 >/proc/sys/net/ipv4/ip_forward'
    ip netns exec "$name" \
       sh -c 'echo 1 >/proc/sys/net/ipv6/conf/all/forwarding'

    add_router_veth "$name" "$id1" "$ip4" "$ip6"
    add_router_veth "$name" "$id2" "$ip4" "$ip6"
    add_router_veth "$name" "$NVME_ROUTER_VLAN" "$ip4" "$ip6"
}

add_routers() {
    local r

    for r in  "$@"; do
	add_router "$r"
    done
}

trap 'echo $0: line ${LINENO}: ERROR in \"$BASH_COMMAND\" >&2; exit 1' ERR
trap 'trap - ERR; echo "=== $0: cleaning up ===" >&2; eval "$CLEANUP"' 0
set -E

[[ "$NVME_USE_OVS" = 1 ]] || exit 0
[[ -f "$CLEANUP_SCRIPT" ]] || exit 0

include_conf_file router.conf

[[ $# -gt 0 ]] || set -- ${NVME_VLAN_ROUTERS}
add_routers "$@"

write_cleanup_script
trap - 0

exit 0
