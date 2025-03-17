#! /bin/sh
. network/defaults.sh

hostn=$(hostname)
hostn=${hostn%%.*}
sudoers_file=/etc/sudoers.d/50-SUSE-nvme-poc

FAT=$(tput smso)$(tput bold)
NOR=$(tput rmso)$(tput sgr0)

QEMU_BRIDGE=""
for i in $(seq 1 "$NVME_N_BRIDGES"); do
    QEMU_BRIDGE="$QEMU_BRIDGE
allow $BRIDGE$i"
done

read -d "" SUDOERS <<EOF
### Recommended sudoers configuration for SUSE NVMeoF-boot PoC
User_Alias NVME_USERS = $USER
Host_Alias NVME_HOSTS = $hostn

Cmd_Alias NVME_CMDS = $PWD/qemu.sh ""
Defaults!NVME_CMDS env_keep += "VM_NAME VM_UUID VM_OVMF_IMG VM_BRIDGE VM_ISO VM_DUD VM_VGA_FLAGS V"
NVME_USERS NVME_HOSTS=(root) NOPASSWD: NVME_CMDS

Cmd_Alias NVME_NET = $PWD/network/setup.sh "", $PWD/network/cleanup.sh "", \\\\
	  $PWD/network/router.sh "", $PWD/network/cleanup-router.sh ""
Defaults!NVME_NET env_keep += "NVME_USE_OVS NVME_N_BRIDGES NVME_N_VLANS V"
NVME_USERS NVME_HOSTS=(root) NOPASSWD: NVME_NET
EOF

cat <<EOF
${FAT}SETTING UP USER ACCESS RIGHTS FOR THE SUSE NVMEOF-BOOT POC${NOR}

User $USER must be able control qemu and libvirt.
Usually that means $USER should be member of the groups "kvm" and "libvirt".

${FAT}Current list of groups that $USER is member of:${NOR}

    $(id -nG "$USER")

${FAT}RECOMMENDED SUDOERS CONFIGURATION${NOR}

User $USER must be able to run certain commands with root rights,
and pass certain environment variables to these commands.

# -------- begin $sudoers_file --------
$SUDOERS
# -------- end $sudoers_file ----------

EOF

if tty &>/dev/null; then
    RESP=
    while [[ ! "$RESP" ]]; do
	echo -n "${FAT}Do you want to install this code as $sudoers_file (type \"YES\" to accept): "
	read RESP
	echo "$NOR"
    done

    if [[ "$RESP" = "YES" ]]; then
	echo "Creating $sudoers_file, you may need to enter credentials"
	sudo tee "$sudoers_file" >/dev/null <<<"$SUDOERS"
	sudo chmod 444 "$sudoers_file"
	echo "${FAT}Please test the new sudoers configuration!${NOR}"
    else
	echo "NOT creating $sudoers_file"
    fi
fi

cat <<EOF

${FAT}RECOMMENDED CONFIGURATION FOR /etc/qemu/bridge.conf${NOR}

# -------- begin current contents of /etc/qemu/bridge.conf --------
$(cat /etc/qemu/bridge.conf || true)
# -------- end current contents of /etc/qemu/bridge.conf ----------

# -------- begin additional content for /etc/qemu/bridge.conf --------
$QEMU_BRIDGE
# -------- end additional content for /etc/qemu/bridge.conf ----------
EOF

if tty &>/dev/null; then
    RESP=
    while [[ ! "$RESP" ]]; do
	echo -n "${FAT}Do you want to add this content to /etc/qemu/bridge.conf (type \"YES\" to accept): "
	read RESP
	echo "$NOR"
    done

    if [[ "$RESP" = "YES" ]]; then
	echo "Modifying /etc/qemu/bridge.conf, you may need to enter credentials"
	sudo tee -a /etc/qemu/bridge.conf >/dev/null <<<"$QEMU_BRIDGE"
    else
	echo "NOT modifying /etc/qemu/bridge.conf"
    fi
fi
