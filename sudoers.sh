#! /bin/sh
hostn=$(hostname)
hostn=${hostn%%.*}

cat <<EOF
###  User $USER must be able control qemu and libvirt
Usually that means $USER should be member of the groups "qemu" and "libvirt"

### Recommended sudoers configuration (add with visudo):
User_Alias NVME_USERS = $USER
Host_Alias NVME_HOSTS = $hostn
Cmd_Alias NVME_CMDS = $PWD/qemu.sh ""
Cmd_Alias NVME_NET = $PWD/network/setup.sh "", $PWD/network/cleanup.sh ""
Defaults!NVME_CMDS env_keep += "VM_NAME VM_UUID VM_OVMF_IMG VM_BRIDGE VM_ISO VM_DUD VM_VGA_FLAGS V"
Defaults!NVME_NET env_keep += "NVME_USE_OVS V"
NVME_USERS NVME_HOSTS=(root) NOPASSWD: NVME_CMDS
NVME_USERS NVME_HOSTS=(root) NOPASSWD: NVME_NET
### End of sudoers config ###

### /etc/qemu/bridge.conf configuration
allow br_nvme

EOF
