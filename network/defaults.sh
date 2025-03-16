# Set environment variables in "network.conf" to override the settings below
# Parameters for calculating IP address ranges
: "${ULA_PREFIX:=fddf:d:f}"
: "${IP4_PREFIX:=192.168}"
: "${NVME_N_VLANS:=2}"
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
