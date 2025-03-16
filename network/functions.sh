push_cleanup() {
    CLEANUP="$@
$CLEANUP"
}

br_ipv4() {
    echo "$IP4_PREFIX.$((SUBNET_BASE - $1))."
}

br_ipv6() {
    printf "%s:bb%02x::" "$ULA_PREFIX" "$1"
}

ovs_ipv4() {
    if [[ "$1" -le "$NVME_N_VLANS" ]]; then
	echo "$IP4_PREFIX.$((SUBNET_BASE + $1))."
    else
	echo "$IP4_PREFIX.$1."
    fi
}

ovs_ipv6() {
    printf "%s:aa%02x::" "$ULA_PREFIX" "$1"
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

write_cleanup_script() {
    cat >"$CLEANUP_SCRIPT" <<EOF
#! /bin/bash
$([ "$V" != 2 ] || echo 'set -x')
[ \$UID -eq 0 ] || exec sudo "\$0"
export LC_ALL=C

! read -r pid < $DNSMASQ_DIR/dnsmasq-nvmeof.pid || kill \$pid
EOF
    eval "echo \"$CLEANUP\"" >>"$CLEANUP_SCRIPT"
    chmod a+x "$CLEANUP_SCRIPT"
    echo "=== $0: to clean up, run $CLEANUP_SCRIPT ===" >&2
}
