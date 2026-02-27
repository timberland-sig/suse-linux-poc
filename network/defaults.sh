# Set environment variables in "network.conf" to override the settings below

# VLAN setup: number of VLANs to create
# 1 is enough for simple VLAN testing
# Complex, routed network topologies will need at least 2 for
# a single connection, and 4 for 2 connections
# Don't set higher than 7.
: "${NVME_N_VLANS:=4}"
# "routers" to create
# "routers" are network namespaces which have access to 2 VLANs
# and route packets between them. "1:2" means that packets will
# be routed between VLAN 1 and 2.
# VLAN ID 0 refers to "no VLAN tag".
# Format: space-separated list of VLAN tuples (x:y).
: "${NVME_VLAN_ROUTERS:="0:1 1:2 3:4"}"

# This VLAN is used to connect "routers" with each other and
# create complex routing scenarios.
: "${NVME_ROUTER_VLAN:=99}"

# Prefix for network namespace names
: "${NVME_ROUTER_NETNS:=router_}"

# "Router" IP address
# IPv6 address ends in ::9:$X:$Y, where X and Y are the VLAN IDs this router
# is connected to
# IPv4 address ends in .$((IPv4_ROUTER_OFFSET + X + 8 * Y)
: "${IPv4_ROUTER_OFFSET:=64}"

# Parameters for calculating IP address ranges
: "${ULA_PREFIX:=fddf:d:f}"
: "${IP4_PREFIX:=192.168}"
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
: "${DHCP_LEASETIME:=3600}"
: "${NQN:=nqn.2014-08.org.nvmexpress.discovery}"
# Use e.g. for root-path assignments or static IPs
: "${DNSMASQ_EXTRA_OPTS:=}"

: "${NVME_N_BRIDGES:=2}"
: "${BRIDGE:=br_nvme}"
: "${BR_MASK:=24}"
: "${BR_PREFIX6:=64}"

: "${OVS_BRIDGE:=ovs_nvme}"
: "${OVS_MASK:=24}"
: "${OVS_PREFIX6:=64}"

# Set this in network.conf to override the server name
# in the DHCP root-path option (e.g. for using the IP address of the server)
# the default is the server's FQDN
: "${BR_RP_SERVER:=}"
: "${OVS_RP_SERVER:=}"

# Set to last element of gateway to enable routing
# e.g. 5 for gateway 192.168.X.5 on all IPv4 networks
: "${BR_GATEWAY_SUFFIX:=}"
: "${OVS_GATEWAY:=}"


# Directory where to store dnsmasq conf files
# location may depend on security settings (Apparmor)
: "${DNSMASQ_DIR:=/run/dnsmasq}"

# Set to some directory to enable PXE
: "${DNSMASQ_PXE_ROOT:=}"

# hostname of the VM host in DNS
: "${DNSMASQ_NAME:="dad"}"

# DNS forwarder, if any
: "${DNSMASQ_FORWARDER:=}"
