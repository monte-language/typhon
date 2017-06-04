boot_objects = boot/lib/monte/monte_lexer.mast \
	boot/lib/monte/monte_parser.mast \
	boot/lib/monte/monte_expander.mast \
	boot/lib/monte/monte_optimizer.mast \
	boot/lib/monte/monte_verifier.mast \
	boot/lib/monte/mast.mast \
	boot/lib/codec/utf8.mast \
	boot/montec.mast \
	boot/lib/enum.mast \
	boot/lib/iterators.mast \
	boot/lib/streams.mast \
	boot/prelude.mast \
	boot/prelude/monte_ast.mast \
	boot/prelude/b.mast \
	boot/prelude/brand.mast \
	boot/prelude/m.mast \
	boot/prelude/ql.mast \
	boot/prelude/protocolDesc.mast \
	boot/prelude/region.mast \
	boot/prelude/simple.mast \
	boot/prelude/transparent.mast \
	boot/prelude/coreInterfaces.mast

.PRECIOUS: $(boot_objects)

PYTHON=venv/bin/python
MT_TYPHON=./mt-typhon
OPTLEVEL=-O2

ifdef PROFILE
	PROFILE_FLAGS=-p
else
	PROFILE_FLAGS=
endif

# This, being the first rule in the file, will be the default rule to make. It
# is *not* because of the name.
default: mt-typhon mast fun

mt-typhon:
	$(PYTHON) -mrpython $(OPTLEVEL) ./main.py

boot: $(boot_objects) | mt-typhon

$(boot_objects): boot/%: mast/%
	@ echo "BOOT $<"
	@ cp $< $@

mast: mast/lib/enum.mast mast/lib/record.mast \
	mast/lib/amp.mast \
	mast/lib/ansiColor.mast \
	mast/lib/complex.mast \
	mast/lib/continued.mast \
	mast/lib/gai.mast \
	mast/lib/help.mast \
	mast/lib/iterators.mast \
	mast/lib/json.mast \
	mast/lib/marley.mast \
	mast/lib/streams.mast \
	mast/lib/words.mast \
	prelude \
	codec \
	entropy \
	parsers \
	games \
	bench \
	monte

testVM: default
	trial typhon

testMast: default mast mast/tests/lexer.mast mast/tests/parser.mast \
	mast/tests/auditors.mast mast/tests/fail-arg.mast mast/tests/expander.mast \
	mast/tests/optimizer.mast mast/tests/flexMap.mast mast/tests/proptests.mast \
	mast/tests/b.mast mast/tests/region.mast mast/tests/regressions.mast \
	mast/tests/promises.mast
	$(MT_TYPHON) -l mast loader test all-tests

test: testVM testMast

prelude: mast/prelude.mast mast/prelude/brand.mast mast/prelude/m.mast \
	mast/prelude/ast_printer.mast mast/prelude/monte_ast.mast \
	mast/prelude/ql.mast mast/prelude/region.mast \
	mast/prelude/simple.mast mast/prelude/protocolDesc.mast \
	mast/prelude/b.mast mast/prelude/transparent.mast \
	mast/prelude/coreInterfaces.mast

codec: mast/lib/codec.mast mast/lib/codec/utf8.mast mast/lib/codec/percent.mast

entropy: mast/lib/entropy/pool.mast mast/lib/entropy/entropy.mast \
	mast/lib/entropy/xorshift.mast mast/lib/entropy/pi.mast \
	mast/lib/entropy/pcg.mast

parsers: mast/lib/parsers/html.mast \
	mast/lib/parsers/regex.mast

games: mast/games/mafia.mast

fun: mast/fun/elements.mast mast/fun/repl.mast mast/fun/termParser.mast

bench: mast/bench/nqueens.mast mast/bench/richards.mast mast/bench/montstone.mast \
	mast/bench/primeCount.mast mast/bench/brot.mast \
	mast/bench/entropy.mast \
	mast/bench/core.mast \
	mast/benchRunner.mast

monte:  mast/prelude/monte_ast.mast mast/lib/monte/monte_lexer.mast \
	mast/lib/monte/monte_parser.mast mast/lib/monte/monte_expander.mast \
	mast/lib/monte/monte_optimizer.mast \
	mast/lib/monte/mast.mast mast/lib/monte/monte_verifier.mast \
	mast/lib/monte/meta.mast mast/lib/monte/mix.mast \
	mast/montec.mast mast/testRunner.mast mast/all-tests.mast

mast/prelude.mast: mast/prelude.mt
	@ echo "MONTEC-UNSAFE $<"
	@ $(MT_TYPHON) $(PROFILE_FLAGS) -l boot loader run montec -noverify $< $@ # 2> /dev/null

loader.mast: loader.mt
	@ echo "MONTEC-UNSAFE $<"
	@ $(MT_TYPHON) $(PROFILE_FLAGS) -l boot loader run montec -noverify $< $@ # 2> /dev/null

%.mast: %.mt
	@ echo "MONTEC $<"
	@ $(MT_TYPHON) $(PROFILE_FLAGS) -l boot loader run montec $< $@ # 2> /dev/null

clean:
	@ echo "CLEAN"
	@ find -iwholename './mast/*.mast' -delete
