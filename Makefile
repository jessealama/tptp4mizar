JAVA = java
XSLTXT = xsltxt.jar

all: tptp2dco.xsl tptp2dno.xsl tptp2miz.xsl tptp2voc.xsl

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;
