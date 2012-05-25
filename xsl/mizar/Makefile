JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: pp.xsl compress.xsl repair.xsl mizar-to-tptp.xsl patch.xsl add-theorems-to-evl.xsl delete-evl-identifiers.xsl

check:
	# don't know what to do yet

clean:
	rm -f *.xsl
