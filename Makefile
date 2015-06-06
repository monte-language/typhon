boot_objects = boot/montec.ty \
	boot/lib/monte/termParser.ty \
	boot/lib/monte/monte_lexer.ty \
	boot/lib/monte/monte_parser.ty \
	boot/lib/monte/monte_ast.ty \
	boot/lib/monte/monte_expander.ty \
	boot/lib/monte/monte_optimizer.ty \
	boot/lib/bytes.ty \
	boot/lib/codec/utf8.ty \
	boot/lib/tubes/nullPump.ty \
	boot/lib/tubes/mapPump.ty \
	boot/lib/tubes/utf8.ty \
	boot/lib/tubes/pumpTube.ty \
	boot/prelude.ty \
	boot/prelude/brand.ty \
	boot/prelude/region.ty \
	boot/prelude/simple.ty \
	boot/prelude/space.ty

.PRECIOUS: $(boot_objects)

PYTHON=venv/bin/python

ifdef PROFILE
	PROFILE_FLAGS=-p
else
	PROFILE_FLAGS=
endif

# This, being the first rule in the file, will be the default rule to make. It
# is *not* because of the name.
default: mt-typhon mast

mt-typhon:
	$(PYTHON) -m rpython -O2 main

boot: $(boot_objects) | mt-typhon

$(boot_objects): boot/%.ty: mast/%.mt
	@ echo "MONTEC (boot scope) $<"
	@ ./mt-typhon $(PROFILE_FLAGS) -l boot boot/montec.ty $< $@ 2> /dev/null

test: default
	trial typhon
	find mast/lib -name \*.ty -exec ./mt-typhon -l mast {} \;

mast: mast/lib/atoi.ty mast/lib/bytes.ty mast/lib/enum.ty mast/lib/netstring.ty \
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
	@ ./mt-typhon $(PROFILE_FLAGS) -l boot boot/montec.ty $< $@ 2> /dev/null

clean:
	@ echo "CLEAN"
	@ find -iname mast/\*.ty -delete
