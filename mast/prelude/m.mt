def bench(_, _) {null}

def parserScope := [ => Any, => Bool, => Bytes, => Char, => DeepFrozen, => Double, => Empty,
    => Int, => List, => Map, => NullOk, => Same, => Set, => Str,
    => SubrangeGuard, => Void,
    => _mapEmpty, => _mapExtract,
    => _accumulateList, => _accumulateMap, => _booleanFlow, => _iterWhile,
    => _validateFor,
    => _switchFailed, => _makeVerbFacet, => _comparer,
    => _suchThat, => _matchSame, => _bind, => _quasiMatcher,
    => M, => import, => throw, => typhonEval,
    => b__quasiParser, => simple__quasiParser,
    => _makeOrderedSpace, => bench, => astBuilder
]

def [=> makeMonteParser :DeepFrozen] | _ := import.script("lib/parsers/monte",
                                                   parserScope)
def [=> makeMonteLexer :DeepFrozen] | _ := import.script("lib/monte/monte_lexer",
                                                  parserScope)
def [=> parseExpression :DeepFrozen] | _ := import.script("lib/monte/monte_parser",
                                                   parserScope)
def [=> makeLexerQP] | _ := import.script("prelude/ql", parserScope)
def [=> astBuilder :DeepFrozen] | _ := import.script("prelude/monte_ast",
                                              parserScope)
def [=> expand :DeepFrozen] | _ := import.script("lib/monte/monte_expander",
                                          parserScope)
def [=> optimize :DeepFrozen] | _ := import.script("lib/monte/monte_optimizer",
                                            parserScope)


def makeFakeLex(tokens) as DeepFrozen:
    def iter := tokens._makeIterator()

    return object fakeLex:
        to next(ej):
            escape doNotCare:
                return iter.next(doNotCare)[1]
            catch _:
                ej(null)

        to valueHole():
            return 42

        to patternHole():
            return 42


def makeM(ast, isKernel :Bool) as DeepFrozen:
    return object m:
        "An abstract syntax tree in the Monte programming language."

        to _printOn(out):
            out.print("m`")
            ast._printOn(out)
            out.print("`")

        to substitute(values):
            # XXX
            return m

        to expand():
            "Desugar all non-Kernel-Monte syntax into Kernel-Monte."

            if (isKernel):
                return m

            escape ej:
                return makeM(expand(ast, astBuilder, ej), true)
            catch error:
                throw(`Couldn't expand to Kernel-Monte: $error`)

        to mix():
            "Aggressively optimize Kernel-Monte."

            if (!isKernel):
                throw(`Can't optimize unexpanded AST`)

            return makeM(optimize(ast), true)


def makeQL(tokens) as DeepFrozen:
    def ast := parseExpression(makeFakeLex(tokens), astBuilder, throw)
    return makeM(ast, false)

def makeChunkingLexer(inputName :Str):
    def makeLexer() as DeepFrozen:
        var lexer := makeMonteLexer("", inputName)
        var tokens := []

        return object chunkingLexerChunk:
            to feedMany(chunk):
                lexer lexerForNextChunk= (chunk)
                escape ej:
                    while (true):
                        tokens with= (lexer.next(ej))

            to failed():
                return false

            to finished():
                return true

            to results():
                return tokens

    return makeLexer

def [VALUE_HOLE :DeepFrozen,
     PATTERN_HOLE :DeepFrozen] := makeMonteLexer.holes()

def makeValueHole(index) as DeepFrozen:
    return [index, VALUE_HOLE]

def makePatternHole(index) as DeepFrozen:
    return [index, PATTERN_HOLE]

# XXX manual desugaring of extends-syntax to preserve DFness.
def lexerQP :DeepFrozen := makeLexerQP(makeQL, makeChunkingLexer("m``"),
                                       makeValueHole, makePatternHole)
object m__quasiParser extends lexerQP as DeepFrozen:
    "A quasiparser for the Monte programming language.

     This object will parse any Monte expression and return an opaque
     value. In the near future, this object will instead return a translucent
     view into a Monte compiler and optimizer."

    to getAstBuilder():
        return astBuilder

object eval as DeepFrozen:
    to run(source :Str, environment):
        "Evaluate a Monte source expression.

         The expression will be provided only the given environment. No other
         values will be passed in."

        return eval.evalToPair(source, environment)[0]

    to evalToPair(source :Str, environment):
        def parser := makeMonteParser("<eval>")
        parser.feedMany(source)
        if (parser.failed()):
            throw(parser.getFailure())
        else:
            def result := parser.dump()
            return typhonEval.evalToPair(result, environment)

[=> m__quasiParser, => eval]
