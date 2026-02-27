### MAKE CUSTOMIZATIONS IN env-config.mk and vm-config.mk !!! ###

### ADVANCED SETTINGS

# Set to non-empty value to enable autoyast installation with "make inst"
AUTOINST :=

# prefix for constructing the hostname from VM_NAME
NAME_PREFIX := nvmeof-

# Defaults to avoid syntax errors while config.mk doesn't exist
IP4_PREFIX := 192.168
ULA_PREFIX := fddf:d:f
SUBNET_BASE := 50
SERVER_NAME := vagrant-nvmet

# Include config.mk here, and use ?= below to make it possible to override
# derived variables like VM_BRIDGE
include env-config.mk
include vm-config.mk

# URL for downloading OVMF image
OVMF_RELEASE ?= 72976af
OVMF_URL := https://github.com/timberland-sig/edk2/releases/download/release-$(OVMF_RELEASE)/timberland-ovmf-release-$(OVMF_RELEASE).zip

# Avoid shell syntax error below if vm-config.mk doesn't exist yet
VLAN_ID := $(if $(VLAN_ID),$(VLAN_ID),0)
VLAN_ID_1 := $(if $(VLAN_ID_1),$(VLAN_ID_1),0)

### VM NETWORKING
# VM_BRIDGE, TARGET, IPADDR, GATEWAY, SUBSYSNQN are set automatically here.
# It is possible to override them for special setups.

ifeq ($(VM_NETWORK_TYPE),bridge)
VM_BRIDGE ?= br_nvme1
ifneq ($(subst 4,X,$(CONFIG)),$(CONFIG))
SUBNET := $(IP4_PREFIX).$(shell printf %d $$(($(SUBNET_BASE)-1))).
else
SUBNET := $(shell printf "%s:bb%02x::" "$(ULA_PREFIX)" 1)
endif
else
VM_BRIDGE ?= ovs_nvme
ifneq ($(subst 4,X,$(CONFIG)),$(CONFIG))
SUBNET := $(IP4_PREFIX).$(shell printf %d $$(($(SUBNET_BASE)+$(VLAN_ID)))).
else
SUBNET := $(shell printf "%s:aa%02x::" "$(ULA_PREFIX)" $(VLAN_ID))
endif
endif

ifeq ($(CONFIG_1),)
TWO_IFACES := 0
else
TWO_IFACES := 1
ifeq ($(VM_NETWORK_TYPE_1),bridge)
VM_BRIDGE_1 ?= br_nvme1
ifneq ($(subst 4,X,$(CONFIG_1)),$(CONFIG_1))
SUBNET_1 := $(IP4_PREFIX).$(shell printf %d $$(($(SUBNET_BASE)-1))).
else
SUBNET_1 := $(shell printf "%s:bb%02x::" "$(ULA_PREFIX)" 1)
endif
else
VM_BRIDGE_1 ?= ovs_nvme
ifneq ($(subst 4,X,$(CONFIG)),$(CONFIG))
SUBNET_1 := $(IP4_PREFIX).$(shell printf %d $$(($(SUBNET_BASE)+$(VLAN_ID_1)))).
else
SUBNET_1 := $(shell printf "%s:aa%02x::" "$(ULA_PREFIX)" $(VLAN_ID_1))
endif
endif
endif

# The nvmet server IP always ends in .10 or :10, e.g. fddf:d:f:55::10
# The gateway / bridge IP always ends in .1 or :1
TARGET ?= $(SUBNET)10
# Local IP for static configurations
IPADDR ?= $(SUBNET)50
ifeq ($(USE_GW),)
GATEWAY ?=
else
GATEWAY ?= $(SUBNET)1
endif

ifeq ($(TWO_IFACES),1)
TARGET_1 ?= $(SUBNET_1)10
# Local IP for static configurations
IPADDR_1 ?= $(SUBNET_1)51
ifeq ($(USE_GW_1),)
GATEWAY_1 ?=
else
GATEWAY_1 ?= $(SUBNET_1)1
endif
endif

NQN_PREFIX := nqn.2022-12.org.nvmexpress.boot.poc:$(shell echo "$${HOSTNAME%%.*}").vagrant-nvmet
# See subsysnqn_prefix in nvmet-server/group_vars/nvme_servers
ifeq ($(DISCOVERY),)
SUBSYSNQN ?= $(NQN_PREFIX).subsys$(SUBSYS)
else
SUBSYSNQN ?= nqn.2014-08.org.nvmexpress.discovery
endif
ifeq ($(DISCOVERY_1),)
SUBSYSNQN_1 ?= $(NQN_PREFIX).subsys$(SUBSYS)
else
SUBSYSNQN_1 ?= nqn.2014-08.org.nvmexpress.discovery
endif

### END CUSTOMIZATION SECTION ###

##  "Driver" update disk configuration for (open)SUSE
# See https://github.com/openSUSE/mkdud/blob/master/HOWTO.md
# For 15.5, no DUD is needed
ifeq ($(VERSION),15.4)
DUD := nvme.iso
# packages to update during installation
# (jq / libonig is unchanged from base distro, it's just not on the ISO image)
PACKAGES := libnvme1 libnvme-mi1 nvme-cli dracut dracut-mkinitrd-deprecated libjq1 jq libonig4
SCRIPTS := update.pre
else # 15.5 and later: DUD only required for autoinst.xml
PACKAGES :=
ifneq ($(AUTOINST),)
DUD := nvme.iso
else
DUD :=
endif
endif

ifeq ($(BASE_DIST),sle)
SP := $(lastword $(subst ., ,$(VERSION)))
VER := $(firstword $(subst ., ,$(VERSION)))
ifeq ($(VER),15)
ORIG_ISO := SLE-$(VER)-SP$(SP)-Full-x86_64-Media1.iso
else
ORIG_ISO := SLES-$(VERSION)-x86_64.install.iso
endif
else
# Leap ISO image can be downloaded
ISO_URL := https://download.opensuse.org/distribution/leap/$(VERSION)/iso
ORIG_ISO := openSUSE-Leap-$(VERSION)-DVD-x86_64-Media.iso
SP :=
VER := $(VERSION)
endif
ISO := install.iso

# URL to download packages from
PACKAGE_URL := https://download.opensuse.org/repositories/home:/mwilck:/timberland/$(VERSION)
# Local directory with update packages
PACKAGEDIR := $(CURDIR)/packages
# GPG signing keys for packages stored in PACKAGEDIR
KEYS = $(wildcard $(CURDIR)/keys/*.key)

ifneq ($(AUTOINST),)
SCRIPTS += autoinst.xml
endif

EFI_EXES := NvmeOfCli.efi VConfig.efi
.PRECIOUS: $(EFI_EXES:%=efitools/%)
.SUFFIXES:

# distribution name to use for driver update disk, see mkdud man page
DIST := $(BASE_DIST)$(VER)

# Size of EFI disk
EFIDISK_MB := 2

CONFIG_FILE := vm/$(VM_NAME).conf

LIBVIRT_DEFAULT_URI := qemu:///system

-include uuid-$(VM_NAME).mk

export V
export VM_NAME
export NAME_PREFIX
export VM_UUID
export VM_BRIDGE
export VM_BRIDGE_1
export VM_NETWORK_TYPE
export VM_NETWORK_TYPE_1
export VM_VGA_FLAGS
export NVME_MAX_NAMESPACES
export STORAGE_POOL
export NVME_USE_OVS
export NVME_N_BRIDGES
export NVME_N_VLANS
export VLAN_ID
export VLAN_ID_1
export LIBVIRT_DEFAULT_URI
export ULA_PREFIX
export IP4_PREFIX
export SUBNET_BASE
export SERVER_NAME
export OVMF_RELEASE

ALL_CFG := $(VLAN_ID)!$(AUTOINST)!$(CONFIG)!$(TARGET)!$(IPADDR)!$(SUBSYSNQN)$(if $(CONFIG_1),;$(VLAN_ID_1)!$(CONFIG_1)!$(TARGET_1)!$(IPADDR_1)!$(SUBSYSNQN_1),)
OLD_CFG := $(file <current_config)
OLD_VLAN_ID := $(shell x="$(OLD_CFG)"; x=$${x%%!*}; echo "$${x:-0}")
OLD_VLAN_ID_1 := $(shell x="$(OLD_CFG)"; x=$${x\#*;}; x=$${x%%!*}; echo "$${x:-0}")

# Derive MAC from uuid
MACADDR := $(shell echo $(VM_UUID) | sed -E 's/.*(..)(..)(..)/52:54:00:\1:\2:\3/;y/abcdef/ABCDEF/')
MACADDR_1 := $(shell echo $(VM_UUID) | sed -E 's/.*(..)(..)(..)/52:54:01:\1:\2:\3/;y/abcdef/ABCDEF/')

V :=
Q := $(if $(V),,@)
ifeq ($(V),2)
VAGRANT_DBG := --debug
ANSIBLE_VERBOSITY := 2
export ANSIBLE_VERBOSITY
else
VAGRANT_DBG :=
endif

.PHONY: libvirt

default: help

env-config.mk vm-config.mk:
	$(Q)cp $@.in $@

ifneq ($(ALL_CFG),$(file <current_config))
.PHONY: current_config
endif

OVMF_TOOLS := tools/ovmf_vars_dump tools/ovmf_vars_set
tools/%: tools/%.c
	$(CC) -Wall -g -O2 -o $@ $^

efidisk/%.efi: ovmf-$(OVMF_RELEASE)/%.efi | efidisk
	$(Q)ln -f $< $@

current_config: vm-config.mk
	@echo === new config: "$(ALL_CFG)"
	$(Q)echo -n "$(ALL_CFG)" >$@

efidisk keys vm ovmf-$(OVMF_RELEASE):
	$(Q)mkdir -p $@

efidisk/startup.nsh:	vm-config.mk current_config efitools/startup.nsh | efidisk
	@echo === building $@ because of $?
	$(Q)sed 's/@TWO_IFACES@/$(TWO_IFACES)/;s/@VLAN_ID@/$(VLAN_ID)/;s/@OLD_VLAN_ID@/$(OLD_VLAN_ID)/;s/@VLAN_ID_1@/$(VLAN_ID_1)/;s/@OLD_VLAN_ID_1@/$(OLD_VLAN_ID_1)/' efitools/startup.nsh >$@
ifneq ($(V),)
	@echo === $@ ===
	cat $@
endif

# make_config CONFIG VLAN_ID MACADDR IPADDR TARGET GATEWAY UUID FILE NR SUBSYSNQN
# The VLAN ID is appended to the Mac address using "\\%04x" format
make_config = $(shell \
	cp "config/$(1)" "$(8)"; \
	if [ $(2) -gt 0 ]; then \
	    vid="\\\\$$(printf %04X $(2))"; \
	else \
            vid=""; \
	fi; \
	sed -i '\
s/AttemptName:.*/AttemptName:Attempt$(9)/;\
s/MacString:.*/MacString:$(3)'"$$vid"'/;\
s/uuid:.*/uuid:$(VM_UUID)/;\
s/HostId:.*/HostId:$(VM_UUID)/;\
s/HostName:.*/HostName:$(NAME_PREFIX)$(VM_NAME)/;\
s/NQN:.*/NQN:$(10)/;\
s/ConnectTimeout:.*/ConnectTimeout:1000/;\
' $(8); \
	[ ! "$(4)" ] || sed -i 's/LocalIp:.*/LocalIp:$(4)/' $(8); \
	[ ! "$(5)" ] || sed -i 's/TargetIp:.*/TargetIp:$(5)/' $(8); \
	if [ "$(6)" ]; then \
		sed -i 's/Gateway:.*/Gateway:$(6)/' $(8); \
	else \
		sed -i '/Gateway:.*/d' $(8); \
	fi; \
	if [ "$(7)" ]; then \
		sed -i '\
s/uuid:.*/uuid:$(VM_UUID)/;\
s/HostId:.*/HostId:$(VM_UUID)/;\
' $(8); \
	else \
		sed -i '/HostNqn:/d;/HostId/d;' $(8); \
	fi; \
)

.INTERMEDIATE: $(CONFIG_FILE)0 $(CONFIG_FILE)1

$(CONFIG_FILE)0: config/$(CONFIG) current_config | vm
	$(call make_config,$(CONFIG),$(VLAN_ID),$(MACADDR),$(IPADDR),$(TARGET),$(GATEWAY),$(VM_UUID),$@,1,$(SUBSYSNQN))

$(CONFIG_FILE)1: config/$(CONFIG_1) current_config | vm
	$(call make_config,$(CONFIG_1),$(VLAN_ID_1),$(MACADDR_1),$(IPADDR_1),$(TARGET_1),$(GATEWAY_1),,$@,2,$(SUBSYSNQN_1))

$(CONFIG_FILE): $(CONFIG_FILE)0 $(if $(CONFIG_1),$(CONFIG_FILE)1,) config/$(CONFIG_1) current_config
	@echo === building $@ because of $?
	$(Q)cat $(CONFIG_FILE)0 $(if $(CONFIG_1),$(CONFIG_FILE)1,) >$@
ifneq ($(V),)
	@echo === $@ ===
	cat $@
endif

efidisk/Config: $(CONFIG_FILE) current_config efidisk
	$(Q)cp -f $(CONFIG_FILE) $@

efidisk.img:	efidisk/Config efidisk/startup.nsh $(EFI_EXES:%=efidisk/%)
	@echo === building $@ because of $?
	$(Q)truncate -s $(EFIDISK_MB)M $@
	$(Q)mformat -v EFI-NBFT -h 2 -s 1024 -t $(EFIDISK_MB) -i $@ "::"
	$(Q)mcopy -i $@ efidisk/* "::"

ifeq ($(BASE_DIST),sle)
$(ORIG_ISO):
	@echo === Please download $(ORIG_ISO) and copy or link it to this directory
	@false
else
$(ORIG_ISO):
	@echo === Downloading $(ORIG_ISO), please stand by...
	$(Q)wget -q $(ISO_URL)/$(ORIG_ISO)
endif

$(ISO):	$(ORIG_ISO)
	$(Q)ln -s $(ORIG_ISO) $(ISO)

vm/$(VM_NAME)-vars.bin: ovmf-$(OVMF_RELEASE)/OVMF_VARS.fd $(if $(MODIFY_OVMF_VARS),$(CONFIG_FILE) tools/ovmf_vars_set) | vm
	@echo === building $@ because of $?
	$(Q)cp ovmf-$(OVMF_RELEASE)/OVMF_VARS.fd $@
ifneq ($(MODIFY_OVMF_VARS),)
	$(Q)tools/ovmf_vars_set "$@" $(CONFIG_FILE)
endif

vars:	vm/$(VM_NAME)-vars.bin

inst:	vm/$(VM_NAME)-vars.bin $(DUD) $(ISO)
	@echo "Installing VM with UUID=$(VM_UUID) (kill with Ctrl-b x)"
	$(Q)VM_ISO=$(ISO) VM_DUD=$(DUD) ./qemu.sh

qemu:	vm/$(VM_NAME)-vars.bin
	@echo "Starting VM with UUID=$(VM_UUID) (kill with Ctrl-b x)"
	$(Q)VM_ISO= ./qemu.sh

vm/$(VM_NAME).xml:	libvirt/vm.xml libvirt/vm.xslt | vm $(if $(MODIFY_OVMF_VARS),,efidisk.img)
	@echo === building $@ because of $?
	$(Q)VM_ISO=$(ISO) VM_DUD=$(DUD) ./libvirt.sh >$@

libvirt: | vm/$(VM_NAME).xml vm/$(VM_NAME)-vars.bin $(DUD) $(ISO)
	$(Q)virsh define vm/$(VM_NAME).xml

ifneq ($(VM_NAME),)
uuid-$(VM_NAME).mk:
	@echo === building $@
	$(Q)uuid=$$(uuidgen) && echo "VM_UUID := $$uuid" >$@; \
		echo === NEW UUID: $$uuid ===
endif

nvmet-server/group_vars/nvme_servers: uuid-$(VM_NAME).mk nvmet-server/group_vars/nvme_servers.in env-config.mk vm-config.mk
	$(Q)[ -f $@ ] || ./network/setup.sh networks < $@.in > $@
	@echo === inserting UUID in server config
	$(Q)sed -i 's/ffffffff-ffff-ffff-ffff-ffffffffff$(SUBSYS)/$(VM_UUID)/' $@
	$(Q)sed -i 's/^max_namespaces:.*/max_namespaces: $(NVME_MAX_NAMESPACES)/' $@

network/cleanup-dnsmasq.sh:
	@echo "=== Starting dnsmasq"
	$(Q)./network/dnsmasq.sh

dnsmasq-up:	network/cleanup-dnsmasq.sh

dnsmasq-down:
	$(Q)[ ! -x ./network/cleanup-dnsmasq.sh ] || ./network/cleanup-dnsmasq.sh

network/cleanup.sh:
	@echo "=== Bringing up network"
	$(Q)./network/setup.sh

net-up: network/cleanup.sh

nvmet-server/server-running: nvmet-server/group_vars/nvme_servers
	@echo === bringing up nvmet server
	$(Q)cd nvmet-server && vagrant up $(VAGRANT_DBG) --no-destroy-on-error
	$(Q): > $@

server-up: net-up nvmet-server/server-running

server-config: nvmet-server/server-running nvmet-server/group_vars/nvme_servers
	@echo === configuring nvmet server
	$(Q)cd nvmet-server && vagrant provision $(VAGRANT_DBG)

server-down:
	$(Q)[ ! -e nvmet-server/server-running ] || { \
	     echo === shutting down nvmet server; \
	     cd nvmet-server && vagrant halt $(VAGRANT_DBG); \
             rm -f server-running; \
	}

server-destroy: net-down
	@echo "=== DESTROYING nmet server, hit ctrl-c now to abort"
	@sleep 2
	$(Q)cd nvmet-server && vagrant destroy $(VAGRANT_DBG) -f
	$(Q)rm -f nvmet-server/group_vars/nvme_servers

net-down: server-down
	$(Q)[ ! -x ./network/cleanup.sh ] || { \
	    echo "=== Shutting down network"; \
	    ./network/cleanup.sh; \
	}

dud:	$(DUD)

keys/repomd.xml.key:	| keys
	@echo === downloading pubkey for $(PACKAGE_URL)
	cd keys && \
	    wget -q $(PACKAGE_URL)/repodata/repomd.xml.key

timberland-ovmf-$(OVMF_RELEASE).zip:
	@echo === downloading OVMF firmware image from $(OVMF_URL)
	$(Q)wget --no-use-server-timestamps -q -O $@ $(OVMF_URL)

ovmf-$(OVMF_RELEASE)/NvmeOfCli.efi ovmf-$(OVMF_RELEASE)/VConfig.efi ovmf-$(OVMF_RELEASE)/OVMF_CODE.fd ovmf-$(OVMF_RELEASE)/OVMF_VARS.fd: | timberland-ovmf-$(OVMF_RELEASE).zip ovmf-$(OVMF_RELEASE)
	@echo === building $@ because of $?
	$(Q)unzip -DD -d ovmf-$(OVMF_RELEASE) -o $<

OVMF:	ovmf-$(OVMF_RELEASE)/OVMF_CODE.fd

ifneq ($(PACKAGES),)
$(PACKAGEDIR): keys/repomd.xml.key
	$(Q)mkdir -p $@
	@echo === downloading packages from $(PACKAGE_URL)
	$(Q)cd $@ && \
	   wget -q --mirror --no-if-modified-since -np -nd \
	      -R '*debug*' -R '*-devel*' -A '*.x86_64.rpm' $(PACKAGE_URL)/x86_64 || \
	   { rmdir $@; false; }
else
$(PACKAGEDIR):
	$(Q)mkdir -p $@
endif

packages:	| $(PACKAGEDIR)

# packaged mkdud on Leap is buggy (https://github.com/openSUSE/mkdud/pull/40)
# also, non-SUSE distros won't have it anyway
mkdud:
	@echo "=== downloading mkdud"
	$(Q)wget https://raw.githubusercontent.com/openSUSE/mkdud/master/mkdud
	$(Q)chmod a+x ./mkdud

autoinst.xml:	autoinst-$(BASE_DIST).xml
	$(Q)ln $< $@

$(DUD): mkdud $(wildcard $(PACKAGEDIR)/*.x86_64.rpm) $(KEYS) $(SCRIPTS) current_config | $(PACKAGEDIR)
	@echo === building $@ because of $?
	$(Q)rm -f $@
	$(Q)./mkdud --create $@ \
		--name="Update disk for NBFT boot" \
		--install=instsys,repo \
		--dist=$(DIST) $(if $(SP),--condition=ServicePack$(SP)) \
		--format=iso \
		--volume=OEMDRV \
		$(PACKAGES:%=$(PACKAGEDIR)/%-[0-9]*.x86_64.rpm) \
		$(KEYS) $(SCRIPTS)

make help-rootless:
	@./sudoers.sh

help:
	@cat help.txt

vars-clean:
	$(Q)rm -f vm/$(VM_NAME)-vars.bin

libvirt-clean:x
	$(Q)virsh undefine --nvram $(NAME_PREFIX)$(VM_NAME)
	$(Q)rm -f vm/$(VM_NAME).xml

# This does not remove the ovmf-* subdirectories
clean:	net-down vars-clean
	$(Q)rm -rf efidisk packages keys
	$(Q)rm -f $(OVMF_TOOLS)
	$(Q)rm -f efidisk.img $(DUD) *~ vm/*~ vm/*.xml current_config timberland-ovmf-*.zip
	$(Q)rm -f mkdud efitools/NvmeOfCli.efi install.iso autoinst.xml
	$(Q)rm -f nvmet-server/group_vars/nvme_servers vm-config.mk env-config.mk

uuid-clean:	clean
	$(Q)rm -f uuid-$(VM_NAME).mk

all-clean:	server-destroy clean
	$(Q)git clean -d -f -x
