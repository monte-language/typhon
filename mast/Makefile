all: lib/atoi.ty lib/bytes.ty lib/enum.ty lib/netstring.ty \
	lib/regex.ty lib/words.ty \
	lib/percent.ty \
	lib/continued.ty \
	lib/tokenBucket.ty lib/loopingCall.ty lib/singleUse.ty \
	lib/cache.ty lib/paths.ty \
	lib/amp.ty \
	lib/slow/exp.ty \
	prelude \
	codec \
	entropy \
	parsers \
	http \
	irc \
	tubes \
	games \
	bench \
    monte

prelude: prelude.ty prelude/brand.ty prelude/region.ty prelude/simple.ty \
	prelude/space.ty

codec: lib/codec/utf8.ty

entropy: lib/entropy/pool.ty lib/entropy/xorshift.ty lib/entropy/entropy.ty

parsers: lib/parsers/derp.ty lib/parsers/http.ty lib/parsers/html.ty \
	lib/parsers/marley.ty

tubes: lib/tubes/nullPump.ty lib/tubes/mapPump.ty \
	lib/tubes/pumpTube.ty lib/tubes/statefulPump.ty \
	lib/tubes/utf8.ty

http: lib/http/client.ty lib/http/server.ty \
	tubes

irc: lib/irc/client.ty \
	tubes

games: games/mafia.ty

fun: fun/elements.ty fun/repl.ty

bench: bench/nqueens.ty bench/richards.ty bench/montstone.ty

monte: lib/monte/monte_ast.ty lib/monte/monte_lexer.ty \
	lib/monte/monte_parser.ty lib/monte/monte_expander.ty \
	lib/monte/termParser.ty

%.ty: %.mt
	monte -c $< > $@

clean:
	find -iname \*.ty -delete
