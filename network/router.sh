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
CLEANUP='rm -f "$CLEANUP_SCRIPT"'

add_router_veth() {
    local nr=$1 id=$2
    local ns=router$nr
    local intern=rtr${nr}_${id}
    local tmp=__$intern
    local peer=lan$id
    local nr6=$(printf %02x $((nr - 64)))

    ip link add "$intern" type veth peer name "$tmp"
    push_cleanup "ip link del '$intern' || true"

    ovs-vsctl add-port "$OVS_BRIDGE" "$intern" "tag=$id"
    push_cleanup "ovs-vsctl del-port '$OVS_BRIDGE' '$intern'"

    ip link set "$intern" up
    push_cleanup "ip link set '$intern' down"

    ip link set "$tmp" netns "$ns"
    ip netns exec "$ns" \
       ip link set "$tmp" name "$peer"
    push_cleanup "ip netns exec '$ns' ip link del '$peer'"

    ip netns exec "$ns" \
       ip link set "$peer" up
    push_cleanup "ip netns exec '$ns' ip link set '$peer' down"

    ip netns exec "$ns" \
       ip addr add "$(ovs_ipv4 "$id")$nr/$OVS_MASK" dev "$peer"
    ip netns exec "$ns" \
       ip addr add "$(ovs_ipv6 "$id")1:$nr6/$OVS_PREFIX6" dev "$peer"
    push_cleanup "ip netns exec '$ns' ip addr flush '$peer'"
}

add_router() {
    local id1=$1 id2=$2
    local nr

    [[ "$id1" ]]
    [[ "$id2" ]]
    [[ "$id1" -ge 0 ]]
    [[ "$id1" -le 7 ]]
    [[ "$id2" -ge 0 ]]
    [[ "$id2" -le 7 ]]
    [[ "$id1" -ne "$id2" ]]

    nr=$((64 + id1 + 8 * id2))

    echo "$0: creating network namespace 'router$nr'"
    ip netns add "router$nr"
    push_cleanup "ip netns del 'router$nr'"
    push_cleanup "ip netns pids 'router$nr' | xargs -r kill"

    ip netns exec "router$nr" \
       sh -c 'echo 1 >/proc/sys/net/ipv4/ip_forward'
    ip netns exec "router$nr" \
       sh -c 'echo 1 >/proc/sys/net/ipv6/conf/all/forwarding'

    add_router_veth "$nr" "$id1"
    add_router_veth "$nr" "$id2"
}

trap 'echo $0: line ${LINENO}: ERROR in \"$BASH_COMMAND\" >&2; exit 1' ERR
trap 'trap - ERR; echo "=== $0: cleaning up ===" >&2; eval "$CLEANUP"' 0
set -E

include_conf_file router.conf

add_router "$@"

write_cleanup_script
trap - 0

exit 0
