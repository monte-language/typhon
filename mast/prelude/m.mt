def bench(_, _) {null}

def parserScope := [
    => Any, => Bool, => Char, => DeepFrozen, => Double, => Empty, => Int,
    => List, => Map, => NullOk, => Same, => Str, => SubrangeGuard, => Void,
    => __mapEmpty, => __mapExtract,
    => __accumulateList, => __booleanFlow, => __iterWhile, => __validateFor,
    => __switchFailed, => __makeVerbFacet, => __comparer,
    => __suchThat, => __matchSame, => __bind, => __quasiMatcher,
    => M, => import, => throw, => typhonEval,
    => simple__quasiParser, => term__quasiParser, => __makeOrderedSpace,
    => bench,
]

def [=> makeMonteParser] | _ := import("lib/parsers/monte", parserScope)
def [=> makeMonteLexer] | _ := import("lib/monte/monte_lexer", parserScope)
def [=> parseExpression] | _ := import("lib/monte/monte_parser", parserScope)
def [=> makeLexerQP] | _ := import("prelude/ql", parserScope)
def [=> astBuilder] | _ := import("prelude/monte_ast", parserScope)

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

def makeM(ast):
    return object m:
        to _printOn(out):
            out.print("m`")
            ast._printOn(out)
            out.print("`")

        to substitute(values):
            return m

def makeQL(tokens):
    def ast := parseExpression(makeFakeLex(tokens), astBuilder, throw)
    return makeM(ast)

def makeChunkingLexer():
    var lexer := makeMonteLexer("")

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

def m__quasiParser := makeLexerQP(makeQL, makeChunkingLexer(), makeValueHole,
                                  makePatternHole)

def eval(source, environment):
    def parser := makeMonteParser()
    parser.feedMany(source)
    if (parser.failed()):
        throw(parser.getFailure())
    else:
        def result := parser.dump()
        return typhonEval(result, environment)

[=> m__quasiParser, => eval]
