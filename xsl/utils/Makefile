JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: strings.xsl token-strings.xsl trace.xsl die.xsl copy.xsl

clean:
	rm -f *.xsl
