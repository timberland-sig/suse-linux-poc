<?xml version="1.0" encoding="UTF-8"?><!-- -*-xml-*- -->
<xsl:stylesheet version="1.0"
		xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:param name="id"/>
  <xsl:output method="text" omit-xml-declaration="yes"/>
  <xsl:template match="@*|node()">
    <xsl:apply-templates select="@*|node()"/>
  </xsl:template>
  <xsl:template match="/network/portgroup[not(vlan)]">
    <xsl:if test="$id='' or $id='0'">
      <xsl:value-of select="@name"/>
      <xsl:text>&#xa;</xsl:text>
    </xsl:if>
  </xsl:template>
  <xsl:template match="/network/portgroup/vlan[not(@trunk)]/tag">
    <xsl:if test="@id=$id">
      <xsl:value-of select="../../@name"/>
      <xsl:text>&#xa;</xsl:text>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
