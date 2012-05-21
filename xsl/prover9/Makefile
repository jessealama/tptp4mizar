JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: prover92tptp.xsl clausification.xsl tptp2prover9.xsl

clean:
	rm -f *.xsl
