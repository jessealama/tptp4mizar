JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: eprover2wsx.xsl eprover2dco.xsl eprover2dno.xsl eprover2voc.xsl eprover2evl.xsl eprover-safe-skolemizations.xsl eprover2def.xsl eprover2the.xsl normalize-step-names.xsl prefix-skolems.xsl skolemized-problem.xsl

clean:
	rm -f *.xsl
