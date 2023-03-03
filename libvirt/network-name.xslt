<?xml version="1.0" encoding="UTF-8"?><!-- -*-xml-*- -->
<xsl:stylesheet version="1.0"
		xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:param name="bridge"/>
  <xsl:output method="text" omit-xml-declaration="yes"/>
  <xsl:template match="@*|node()">
    <xsl:apply-templates select="@*|node()"/>
  </xsl:template>
  <xsl:template match="/network/bridge">
    <xsl:if test="@name=$bridge">
      <xsl:text>yes&#xa;</xsl:text>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
