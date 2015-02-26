MONTE = ~/monte
MONTE_VENV = ~/monte/local_monte


all: prelude.ty lib/atoi.ty lib/bytes.ty lib/enum.ty lib/netstring.ty \
	lib/regex.ty lib/utf8.ty \
	lib/tokenBucket.ty lib/loopingCall.ty \
	lib/paths.ty \
	builtin \
	parsers \
	http \
	irc \
	tubes \
	games \
	bench

builtin: lib/brand.ty lib/simple.ty

parsers: lib/parsers/derp.ty lib/parsers/html.ty

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
	$(MONTE_VENV)/bin/python $(MONTE)/bin/monte -c $< > $@
