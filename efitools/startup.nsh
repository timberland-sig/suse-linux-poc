@echo -off
@set OLD_VLAN_ID @OLD_VLAN_ID@
@set VLAN_ID @VLAN_ID@
if %OLD_VLAN_ID% gt 0 and %OLD_VLAN_ID% ne %VLAN_ID% then
   VConfig -d eth0.%OLD_VLAN_ID%
endif
if %VLAN_ID% gt 0 then
   VConfig -a eth0 %VLAN_ID%
endif
echo "== Current VLAN configuration =="
VConfig -l
echo "== Setting NVMeoF attempt data =="
NvmeOfCli setattempt Config
stall 5000000
exit
