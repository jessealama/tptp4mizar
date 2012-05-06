JAVA = java
XSLTXT = ../xsltxt.jar

%.xsl: %.xsltxt
	$(JAVA) -jar $(XSLTXT) toXSL $*.xsltxt $*.xsl || rm $*.xsl;

all: ivy2wsx.xsl ivy2dco.xsl ivy2dno.xsl ivy2voc.xsl ivy2evl.xsl

clean:
	rm -f *.xsl
