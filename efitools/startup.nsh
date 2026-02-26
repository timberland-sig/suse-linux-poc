@echo -off
@set TWO_IFACES @TWO_IFACES@
@set OLD_VLAN_ID @OLD_VLAN_ID@
@set OLD_VLAN_ID_1 @OLD_VLAN_ID_1@
@set VLAN_ID @VLAN_ID@
@set VLAN_ID_1 @VLAN_ID_1@

if %OLD_VLAN_ID% gt 0 and %OLD_VLAN_ID% ne %VLAN_ID% then
   VConfig -d eth0.%OLD_VLAN_ID%
endif
if %VLAN_ID% gt 0 then
   VConfig -a eth0 %VLAN_ID%
endif

if %TWO_IFACES% eq 1 then
if %OLD_VLAN_ID_1% gt 0 and %OLD_VLAN_ID_1% ne %VLAN_ID_1% then
   VConfig -d eth1.%OLD_VLAN_ID_1%
endif
if %VLAN_ID_1% gt 0 then
   VConfig -a eth1 %VLAN_ID_1%
endif
endif

echo "== Current VLAN configuration =="
VConfig -l
echo "== Setting NVMeoF attempt data =="
NvmeOfCli setattempt Config
stall 5000000
exit
