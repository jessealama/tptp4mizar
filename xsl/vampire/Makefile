JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: vampire2voc.xsl vampire2evl.xsl vampire2dno.xsl vampire2dco.xsl vampire2wsx.xsl vampire2the.xsl repair-vampire.xsl

clean:
	rm -f *.xsl
