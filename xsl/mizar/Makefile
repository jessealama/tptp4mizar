JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: pp.xsl compress.xsl repair.xsl mizar-to-tptp.xsl

clean:
	rm -f *.xsl
