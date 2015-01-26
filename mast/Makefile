all: prelude.ty lib/bytes.ty lib/netstring.ty lib/simple.ty \
	lib/parsers/derp.ty lib/regex.ty lib/utf8.ty \
	http \
	irc \
	tubes

tubes: lib/tubes/nullPump.ty lib/tubes/mapPump.ty \
	lib/tubes/pumpTube.ty \
	lib/tubes/unpauser.ty

http: lib/http/client.ty lib/http/server.ty \
	tubes

irc: lib/irc/client.ty \
	tubes

%.ty: %.mt
	~/monte/local-monte/bin/python ~/monte/bin/monte -c $< > $@
