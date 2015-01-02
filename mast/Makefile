all: prelude.ty lib/bytes.ty lib/netstring.ty lib/simple.ty \
	lib/http/client.ty lib/http/server.ty lib/parsers/derp.ty lib/regex.ty \
	lib/tubes/mapPump.ty lib/tubes/pumpTube.ty lib/tubes/unpauser.ty \
	lib/utf8.ty

%.ty: %.mt
	~/monte/local-monte/bin/python ~/monte/bin/monte -c $< > $@
