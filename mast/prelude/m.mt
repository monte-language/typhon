def bench(_, _) {null}

def parserScope := [
    => Any, => Bool, => Bytes, => Char, => DeepFrozen, => Double, => Empty,
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

def [=> makeMonteParser] | _ := import("lib/parsers/monte", parserScope)
def [=> makeMonteLexer] | _ := import("lib/monte/monte_lexer", parserScope)
def [=> parseExpression] | _ := import("lib/monte/monte_parser", parserScope)
def [=> makeLexerQP] | _ := import("prelude/ql", parserScope)
def [=> astBuilder] | _ := import("prelude/monte_ast", parserScope)
def [=> expand] | _ := import("lib/monte/monte_expander", parserScope)
def [=> optimize] | _ := import("lib/monte/monte_optimizer", parserScope)


def makeFakeLex(tokens):
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


def makeM(ast, isKernel :Bool):
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


def makeQL(tokens):
    def ast := parseExpression(makeFakeLex(tokens), astBuilder, throw)
    return makeM(ast, false)

def makeChunkingLexer(inputName):
    var lexer := makeMonteLexer("", inputName)

    def makeLexer():
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

def makeValueHole(index):
    return [index, makeMonteLexer.holes()[0]]

def makePatternHole(index):
    return [index, makeMonteLexer.holes()[1]]

object m__quasiParser extends makeLexerQP(makeQL, makeChunkingLexer("m``"),
                                          makeValueHole, makePatternHole):
    "A quasiparser for the Monte programming language.

     This object will parse any Monte expression and return an opaque
     value. In the near future, this object will instead return a translucent
     view into a Monte compiler and optimizer."

object eval:
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
