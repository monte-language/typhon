MONTE = ~/repos/monte/monte
MONTE_VENV = ~/repos/monte/monte/v

all: lib/atoi.ty lib/bytes.ty lib/enum.ty lib/netstring.ty \
	lib/regex.ty lib/utf8.ty lib/words.ty \
	lib/tokenBucket.ty lib/loopingCall.ty lib/singleUse.ty \
	lib/cache.ty lib/paths.ty \
	lib/amp.ty \
	prelude \
	entropy \
	parsers \
	http \
	irc \
	tubes \
	games \
	bench

prelude: prelude.ty prelude/brand.ty prelude/region.ty prelude/simple.ty \
	prelude/space.ty

entropy: lib/entropy/pool.ty lib/entropy/xorshift.ty lib/entropy/entropy.ty

parsers: lib/parsers/derp.ty lib/parsers/http.ty lib/parsers/html.ty \
	lib/parsers/marley.ty

tubes: lib/tubes/nullPump.ty lib/tubes/mapPump.ty \
	lib/tubes/pumpTube.ty lib/tubes/statefulPump.ty

http: lib/http/client.ty lib/http/server.ty \
	tubes

irc: lib/irc/client.ty \
	tubes

games: games/mafia.ty

bench: bench/nqueens.ty bench/richards.ty bench/montstone.ty

%.ty: %.mt
	$(MONTE_VENV)/bin/python $(MONTE)/bin/monte -c $< > $@

clean: 
	find -iname \*.ty -delete
