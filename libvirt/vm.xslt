<?xml version="1.0" encoding="UTF-8"?><!-- -*-xml-*- -->
<xsl:stylesheet version="1.0"
		xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
		xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <xsl:param name="name"/>
  <xsl:param name="uuid"/>
  <xsl:param name="ovmf_code"/>
  <xsl:param name="ovmf_vars"/>
  <xsl:param name="network_type"/>
  <xsl:param name="network"/>
  <xsl:param name="portgroup"/>
  <xsl:param name="mac_address"/>
  <xsl:param name="iso"/>
  <xsl:param name="dud"/>
  <xsl:param name="ovmf_log"/>
  <xsl:param name="serial_log"/>
  <xsl:param name="qemu_debug"/>
  <xsl:param name="efidisk"/>
  <xsl:output method="xml" indent="yes"/>
  <xsl:strip-space elements="*"/>
  <xsl:template match="@*|node()" name="copy">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
  <xsl:template name="set-or-keep">
    <xsl:param name="passed"/>
    <xsl:choose>
      <xsl:when test="$passed!=''">
	<xsl:value-of select="$passed"/>
      </xsl:when>
      <xsl:otherwise>
	<xsl:value-of select="."/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template name="set-or-default">
    <xsl:param name="passed"/>
    <xsl:param name="default"/>
    <xsl:choose>
      <xsl:when test="$passed!=''">
	<xsl:value-of select="$passed"/>
      </xsl:when>
      <xsl:otherwise>
	<xsl:value-of select="$default"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template match="/domain/name">
    <name>
      <xsl:call-template name="set-or-keep">
	<xsl:with-param name="passed" select="$name"/>
      </xsl:call-template>
    </name>
  </xsl:template>
  <xsl:template match="/domain/uuid">
    <uuid>
      <xsl:call-template name="set-or-keep">
	<xsl:with-param name="passed" select="$uuid"/>
      </xsl:call-template>
    </uuid>
  </xsl:template>
  <xsl:template match="/domain/os/loader">
    <loader>
      <xsl:apply-templates select="@*"/>
      <xsl:call-template name="set-or-keep">
	<xsl:with-param name="passed" select="$ovmf_code"/>
      </xsl:call-template>
    </loader>
  </xsl:template>
  <xsl:template match="/domain/os/nvram">
    <nvram>
      <xsl:call-template name="set-or-keep">
	<xsl:with-param name="passed" select="$ovmf_vars"/>
      </xsl:call-template>
    </nvram>
  </xsl:template>
  <xsl:template match="/domain/devices/disk[@device='cdrom'][position()='1']/source">
    <xsl:if test="$iso!=''">
      <source>
	<xsl:attribute name="file">
	  <xsl:value-of select="$iso"/>
	</xsl:attribute>
      </source>
    </xsl:if>
  </xsl:template>
  <xsl:template match="/domain/devices/disk[@device='cdrom'][position()='2']/source">
    <xsl:if test="$dud!=''">
      <source>
	<xsl:attribute name="file">
	  <xsl:value-of select="$dud"/>
	</xsl:attribute>
      </source>
    </xsl:if>
  </xsl:template>
  <xsl:template match="/domain/devices/serial[@type='pty' and position()='1']">
    <serial>
      <xsl:apply-templates select="@*"/>
      <xsl:if test="$serial_log!=''">
	<log>
	  <xsl:attribute name="file">
	    <xsl:value-of select="$serial_log"/>
	  </xsl:attribute>
	</log>
      </xsl:if>
      <xsl:apply-templates select="node()[name(.)!='log']"/>
    </serial>
  </xsl:template>
  <xsl:template match="/domain/devices/console[@type='pty' and position()='1']">
    <console>
      <xsl:apply-templates select="@*"/>
      <xsl:if test="$serial_log!=''">
	<log>
	  <xsl:attribute name="file">
	    <xsl:value-of select="$serial_log"/>
	  </xsl:attribute>
	</log>
      </xsl:if>
      <xsl:apply-templates select="node()[name(.)!='log']"/>
    </console>
  </xsl:template>
  <xsl:template match="/domain/devices/interface[@type='network' and position()='1']">
    <interface>
      <xsl:attribute name="type">network</xsl:attribute>
      <xsl:apply-templates select="@*"/>
      <mac>
	<xsl:attribute name="address">
	  <xsl:call-template name="set-or-default">
	    <xsl:with-param name="passed" select="$mac_address"/>
	    <xsl:with-param name="default" select="mac/@address"/>
	  </xsl:call-template>
	</xsl:attribute>
      </mac>
      <source>
	<xsl:attribute name="network">
	  <xsl:call-template name="set-or-default">
	    <xsl:with-param name="passed" select="$network"/>
	    <xsl:with-param name="default" select="source/@network"/>
	  </xsl:call-template>
	</xsl:attribute>
	<xsl:if test="not($portgroup='')">
	  <xsl:attribute name="portgroup">
	    <xsl:value-of select="$portgroup"/>
	  </xsl:attribute>
	</xsl:if>
      </source>
      <rom>
	<xsl:attribute name="bar">off</xsl:attribute>
      </rom>
      <xsl:apply-templates select="node()[name(.)!='source' and name(.)!='mac'
				   and name(.)!='rom']"/>
    </interface>
  </xsl:template>
  <xsl:template match="/domain/devices/disk[@device='disk'][position()='1']/source">
    <xsl:if test="$efidisk!=''">
      <source>
	<xsl:attribute name="file">
	  <xsl:value-of select="$efidisk"/>
	</xsl:attribute>
      </source>
    </xsl:if>
  </xsl:template>
  <xsl:template match="/domain">
    <domain type="kvm"  xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
      <xsl:apply-templates select="@*|node()"/>
      <xsl:if test="$ovmf_log!=''">
	<qemu:commandline>
	  <qemu:arg>
	    <xsl:attribute name="value">-global</xsl:attribute>
	  </qemu:arg>
	  <qemu:arg>
	    <xsl:attribute name="value">isa-debugcon.iobase=0x402</xsl:attribute>
	  </qemu:arg>
	  <qemu:arg>
	    <xsl:attribute name="value">-debugcon</xsl:attribute>
	  </qemu:arg>
	  <qemu:arg>
	    <xsl:attribute name="value">file:<xsl:value-of select="$ovmf_log"/></xsl:attribute>
	  </qemu:arg>
	  <xsl:if test="$qemu_debug!=''">
	    <qemu:arg>
	      <xsl:attribute name="value">-s</xsl:attribute>
	    </qemu:arg>
	  </xsl:if>
	</qemu:commandline>
      </xsl:if>
    </domain>
  </xsl:template>
</xsl:stylesheet>
