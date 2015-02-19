all: prelude.ty lib/atoi.ty lib/bytes.ty lib/enum.ty lib/netstring.ty \
	lib/simple.ty lib/parsers/derp.ty lib/regex.ty lib/utf8.ty \
	lib/tokenBucket.ty lib/loopingCall.ty \
	http \
	irc \
	tubes \
	games \
	bench

tubes: lib/tubes/nullPump.ty lib/tubes/mapPump.ty \
	lib/tubes/pumpTube.ty \
	lib/tubes/unpauser.ty

http: lib/http/client.ty lib/http/server.ty \
	tubes

irc: lib/irc/client.ty \
	tubes

games: games/mafia.ty

bench: bench/nqueens.ty bench/richards.ty bench/montstone.ty

%.ty: %.mt
	~/monte/local-monte/bin/python ~/monte/bin/monte -c $< > $@
