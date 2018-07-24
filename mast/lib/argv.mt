import "unittest" =~ [=> unittest :Any]
exports (flags)

def makeFlagRunner(trie) as DeepFrozen:
    return def flagRunner(argv :List[Str]):
        # Which arg are we on?
        var i :Int := 0
        def s :Int := argv.size()
        # Positional non-flag arguments.
        def pos := [].diverge()
        while (i < s):
            def cont := __continue
            def next := argv[i]
            # We advance immediately, so that we don't grab this entry again
            # and in the hopes that we won't be stuck in this loop forever.
            i += 1
            var t := trie
            for j => c in (next):
                if (j == 0):
                    if (c != '-'):
                        # Not actually a flag, but a positional argument.
                        pos.push(next)
                        # Step the big loop instead of continuing with the
                        # rest of the flag logic.
                        cont(null)
                else:
                    t fetch= (c, fn {
                        # XXX be prettier and more useful
                        throw("Can't make progress", t)
                    })
            if (t =~ [arity, block]):
                def [[], lambda] := block()
                # Slice and advance.
                def args := argv.slice(i, i + arity)
                i += arity
                if (args.isEmpty()):
                    lambda()
                else:
                    escape ej:
                        M.call(lambda, "run", args + [ej], [].asMap())
                    catch problem:
                        # XXX unhelpful
                        throw(`Flag block rejected $args: $problem`)
            else:
                # XXX ugly
                throw("Ambiguous flag", t)
        return pos.snapshot()

def snapshotTrie(trie) as DeepFrozen:
    return if (trie =~ l :List) { l } else {
        [for k => v in (trie) k => snapshotTrie(v)]
    }

def flags.control(verb :Str, ==0, arity :Int, block) as DeepFrozen:
    "Build a structure which can parse argv flags."

    def trie := [].asMap().diverge()

    def push(v, val):
        # We need to nab the ultimate spot in the iteration, and there's not
        # really a good pattern for this yet.
        var prev := var t := trie
        var lastx := null
        for x in (v):
            lastx := x
            prev := t
            t fetch= (x, fn { t[x] := [].asMap().diverge() })
        # Patch that final iteration.
        prev[lastx] := val

    push(verb, [arity, block])

    return object flagTrieBuilder:
        to control(nextVerb :Str, ==0, nextArity :Int, nextBlock):
            push(nextVerb, [nextArity, nextBlock])
            return flagTrieBuilder

        to controlRun():
            return makeFlagRunner(snapshotTrie(trie))

def testFlagsParams(assert):
    def argv := ["one", "-foo", "yes", "42", "two", "-bar", "5", "three"]
    def parser := flags () foo f, via (_makeInt) g {
        assert.equal(f, "yes")
        assert.equal(g, 42)
    } bar via (_makeInt) b {
        assert.equal(b, 5)
    }
    assert.equal(parser(argv), ["one", "two", "three"])

unittest([
    testFlagsParams,
])
