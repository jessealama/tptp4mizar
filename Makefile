all:
	make -C xsl

check:
	make -C bin check
	make -C lib check
	make -C xsl check
	make -C lisp check
