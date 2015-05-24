boot_objects = boot/lib/bytes.ty boot/lib/monte/monte_lexer.ty boot/prelude.ty boot/prelude/space.ty boot/lib/codec/utf8.ty boot/lib/monte/monte_parser.ty boot/prelude/brand.ty boot/lib/monte/monte_ast.ty boot/lib/monte/termParser.ty boot/prelude/region.ty boot/lib/monte/monte_expander.ty boot/lib/monte/monte_optimizer.ty boot/montec.ty boot/prelude/simple.ty
.PRECIOUS: $(boot_objects)

PYTHON=venv/bin/python

mt-typhon:
	$(PYTHON) -m rpython -Ojit main

boot: $(boot_objects) | mt-typhon

$(boot_objects): boot/%.ty: mast/%.mt
	@ echo "MONTEC (boot scope) $<"
	@ ./mt-typhon -l boot boot/montec.ty $< $@


all: mast/lib/atoi.ty mast/lib/bytes.ty mast/lib/enum.ty mast/lib/netstring.ty \
	mast/lib/regex.ty mast/lib/words.ty \
	mast/lib/percent.ty \
	mast/lib/continued.ty \
	mast/lib/tokenBucket.ty mast/lib/loopingCall.ty mast/lib/singleUse.ty \
	mast/lib/cache.ty mast/lib/paths.ty \
	mast/lib/amp.ty \
	mast/lib/slow/exp.ty \
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

prelude: mast/prelude.ty mast/prelude/brand.ty mast/prelude/region.ty mast/prelude/simple.ty \
	mast/prelude/space.ty

codec: mast/lib/codec/utf8.ty

entropy: mast/lib/entropy/pool.ty mast/lib/entropy/xorshift.ty mast/lib/entropy/entropy.ty

parsers: mast/lib/parsers/derp.ty mast/lib/parsers/http.ty mast/lib/parsers/html.ty \
	mast/lib/parsers/marley.ty

tubes: mast/lib/tubes/nullPump.ty mast/lib/tubes/mapPump.ty \
	mast/lib/tubes/pumpTube.ty mast/lib/tubes/statefulPump.ty \
	mast/lib/tubes/utf8.ty \
	mast/lib/tubes/chain.ty

http: mast/lib/http/client.ty mast/lib/http/server.ty \
	tubes

irc: mast/lib/irc/client.ty mast/lib/irc/user.ty \
	tubes

games: mast/games/mafia.ty

fun: mast/fun/elements.ty mast/fun/repl.ty

bench: mast/bench/nqueens.ty mast/bench/richards.ty mast/bench/montstone.ty

monte: mast/lib/monte/monte_ast.ty mast/lib/monte/monte_lexer.ty \
	mast/lib/monte/monte_parser.ty mast/lib/monte/monte_expander.ty \
	mast/lib/monte/monte_optimizer.ty \
	mast/lib/monte/termParser.ty

%.ty: %.mt
	@ echo "MONTEC $<"
	@ ./mt-typhon -l boot boot/montec.ty $< $@

clean:
	@ echo "CLEAN"
	@ find -iname mast/\*.ty -delete
