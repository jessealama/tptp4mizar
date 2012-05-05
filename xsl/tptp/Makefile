JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: tptp-formulas.xsl tptp2voc.xsl tptp2evl.xsl tptp2dno.xsl tptp2dco.xsl tptp2wsx.xsl render-tptp.xsl

clean:
	rm -f *.xsl
