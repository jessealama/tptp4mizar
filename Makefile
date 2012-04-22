JAVA = java
XSLTXT = xsltxt.jar

all: tptp2dco.xsl tptp2dno.xsl tptp2miz.xsl tptp2voc.xsl eprover-ordering.xsl eprover-tstp2miz.xsl sort-tstp.xsl tptp2evl.xsl

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;
