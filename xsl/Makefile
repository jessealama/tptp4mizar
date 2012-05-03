JAVA = java
XSLTXT = xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: eprover2wsx.xsl eprover2dco.xsl eprover2dno.xsl eprover2voc.xsl eprover2evl.xsl eprover-safe-skolemizations.xsl eprover2def.xsl number-symbols.xsl conditional-definition.xsl eprover2the.xsl clean-eprover.xsl compress.xsl tptp-formulas.xsl strings.xsl tstp2wsx.xsl vampire2voc.xsl vampire2evl.xsl vampire2dno.xsl vampire2dco.xsl vampire2wsx.xsl
