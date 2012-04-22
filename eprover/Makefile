JAVA = java
XSLTXT = ../xsltxt.jar

all: tstp2dco.xsl tstp2dno.xsl tstp2miz.xsl tstp2voc.xsl formula-dependencies.xsl tstp2miz.xsl tstp2evl.xsl

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;
