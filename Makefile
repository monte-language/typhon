boot_objects = boot/lib/monte/monte_lexer.mast \
	boot/lib/monte/monte_parser.mast \
	boot/lib/monte/ast_dumper.mast \
	boot/lib/monte/monte_expander.mast \
	boot/lib/monte/monte_optimizer.mast \
	boot/lib/monte/monte_verifier.mast \
	boot/lib/monte/mast.mast \
	boot/lib/codec/utf8.mast \
	boot/lib/parsers/monte.mast \
	boot/montec.mast \
	boot/lib/tubes.mast \
	boot/prelude.mast \
	boot/prelude/monte_ast.mast \
	boot/prelude/b.mast \
	boot/prelude/brand.mast \
	boot/prelude/m.mast \
	boot/prelude/ql.mast \
	boot/prelude/deepfrozen.mast \
	boot/prelude/protocolDesc.mast \
	boot/prelude/region.mast \
	boot/prelude/simple.mast \
	boot/prelude/space.mast \
	boot/prelude/transparent.mast \
	boot/prelude/coreInterfaces.mast

.PRECIOUS: $(boot_objects)

PYTHON=venv/bin/python

ifdef PROFILE
	PROFILE_FLAGS=-p
else
	PROFILE_FLAGS=
endif

# This, being the first rule in the file, will be the default rule to make. It
# is *not* because of the name.
default: mt-typhon mast fun

mt-typhon:
	$(PYTHON) -m rpython -O2 main

boot: $(boot_objects) | mt-typhon

$(boot_objects): boot/%: mast/%
	@ echo "BOOT $<"
	@ cp $< $@

mast: mast/lib/atoi.mast mast/lib/enum.mast mast/lib/record.mast \
	mast/lib/netstring.mast \
	mast/lib/regex.mast mast/lib/words.mast \
	mast/lib/continued.mast \
	mast/lib/tokenBucket.mast mast/lib/loopingCall.mast mast/lib/singleUse.mast \
	mast/lib/cache.mast mast/lib/paths.mast \
	mast/lib/amp.mast \
	mast/lib/slow/exp.mast \
	mast/lib/ansiColor.mast \
	mast/lib/json.mast \
	mast/lib/help.mast \
	mast/lib/complex.mast \
	mast/lib/gai.mast \
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

infer: mast mast/tools/infer.mast

testVM: default
	trial typhon

testMast: default mast infer mast/tests/lexer.mast mast/tests/parser.mast \
	mast/tests/auditors.mast mast/tests/fail-arg.mast mast/tests/expander.mast \
	mast/tests/optimizer.mast mast/tests/flexMap.mast
	./mt-typhon -l mast mast/unittest all-tests

test: testVM testMast

prelude: mast/prelude.mast mast/prelude/brand.mast mast/prelude/m.mast \
	mast/prelude/monte_ast.mast mast/prelude/ql.mast mast/prelude/region.mast \
	mast/prelude/simple.mast mast/prelude/space.mast mast/prelude/deepfrozen.mast \
	mast/prelude/protocolDesc.mast mast/prelude/b.mast mast/prelude/transparent.mast \
	mast/prelude/coreInterfaces.mast

codec: mast/lib/codec.mast mast/lib/codec/utf8.mast mast/lib/codec/percent.mast

entropy: mast/lib/entropy/pool.mast mast/lib/entropy/entropy.mast \
	mast/lib/entropy/xorshift.mast mast/lib/entropy/pi.mast \
	mast/lib/entropy/pcg.mast

parsers: mast/lib/parsers/http.mast mast/lib/parsers/html.mast \
	mast/lib/parsers/marley.mast mast/lib/parsers/monte.mast

tubes: mast/lib/tubes.mast

http: mast/lib/http/client.mast mast/lib/http/server.mast \
	mast/lib/http/tag.mast mast/lib/http/resource.mast \
	tubes

irc: mast/lib/irc/client.mast mast/lib/irc/user.mast \
	tubes

games: mast/games/mafia.mast mast/lib/uKanren.mast

fun: mast/fun/elements.mast mast/fun/repl.mast mast/fun/termParser.mast

bench: mast/bench/nqueens.mast mast/bench/richards.mast mast/bench/montstone.mast \
	mast/bench/primeCount.mast mast/bench/brot.mast mast/bench.mast

monte:  mast/prelude/monte_ast.mast mast/lib/monte/monte_lexer.mast \
	mast/lib/monte/monte_parser.mast mast/lib/monte/monte_expander.mast \
	mast/lib/monte/monte_optimizer.mast mast/lib/monte/ast_dumper.mast \
	mast/lib/monte/mast.mast mast/lib/monte/monte_verifier.mast \
	mast/montec.mast mast/unittest.mast mast/all-tests.mast

%.mast: %.mt
	@ echo "MONTEC $<"
	@ ./mt-typhon $(PROFILE_FLAGS) -l boot boot/montec -mix -format mast $< $@ # 2> /dev/null

clean:
	@ echo "CLEAN"
	@ find -iname mast/\*.mast -delete
