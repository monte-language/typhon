def bench(_, _) {null}

def parserScope := [
    => Any, => Bool, => Char, => DeepFrozen, => Double, => Empty, => Int,
    => List, => Map, => NullOk, => Same, => Str, => SubrangeGuard, => Void,
    => __mapEmpty, => __mapExtract,
    => __accumulateList, => __booleanFlow, => __iterWhile, => __validateFor,
    => __switchFailed, => __makeVerbFacet, => __comparer,
    => __suchThat, => __matchSame, => __bind, => __quasiMatcher,
    => M, => import, => throw, => typhonEval,
    => simple__quasiParser, => __makeOrderedSpace, => bench,
]

def [=> makeMonteParser] | _ := import("lib/parsers/monte", parserScope)

object m:
    pass

def eval(source, environment):
    def parser := makeMonteParser()
    parser.feedMany(source)
    if (parser.failed()):
        throw(parser.getFailure())
    else:
        def result := parser.dump()
        return typhonEval(result, environment)

["m__quasiParser" => m, => eval]
