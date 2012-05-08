JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: sort-tstp.xsl tstp-dependencies.xsl tstp2wsx.xsl normalize-step-names.xsl tstp2dco.xsl

clean:
	rm -f *.xsl
