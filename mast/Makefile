all: prelude.ty lib/atoi.ty lib/bytes.ty lib/enum.ty lib/netstring.ty \
	lib/simple.ty lib/regex.ty \
	lib/tokenBucket.ty lib/loopingCall.ty \
	lib/comp.ty \
	http \
	irc \
	tubes \
	games \
	bench
	# These are broken
	# lib/parsers/derp.ty lib/utf8.ty

tubes: lib/tubes/nullPump.ty lib/tubes/mapPump.ty \
	lib/tubes/pumpTube.ty \
	lib/tubes/unpauser.ty

http: lib/http/client.ty lib/http/server.ty \
	tubes

irc: lib/irc/client.ty \
	tubes

games: games/mafia.ty

bench: bench/nqueens.ty

%.ty: %.mt
	~/src/monte/venv/bin/python ~/src/monte/bin/monte -c $< > $@

clean:
	find -name '*.ty' -delete
