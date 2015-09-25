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

def makeQuasiAstTransformer(values) as DeepFrozen:
    return def monteQAstTransformer(node, maker, args, span):
        return switch (node.getNodeName()) {
            match =="ValueHoleExpr" {
                values[node.getIndex()]
            }
            match =="ValueHolePattern" {
                values[node.getIndex()]
            }
            match =="PatternHoleExpr" {
                throw("Pattern-holes not allowed in QL exprs")
            }
            match =="PatternHolePattern" {
                throw("Pattern-holes not allowed in QL exprs")
            }
            match _ {
                M.call(maker, "run", args + [span], [].asMap())
            }
        }
def [VALUE_HOLE :DeepFrozen,
     PATTERN_HOLE: DeepFrozen] := makeMonteLexer.holes()
def Ast :DeepFrozen := astBuilder.getAstGuard()
def Pattern :DeepFrozen := astBuilder.getPatternGuard()
def Expr :DeepFrozen := astBuilder.getExprGuard()
def NamePattern :DeepFrozen := astBuilder.getNamePatternGuard()
def Noun :DeepFrozen := astBuilder.getNounGuard()

def makeM(ast, isKernel :Bool) as DeepFrozen:
    return object m extends ast:
        "An abstract syntax tree in the Monte programming language."

        to _printOn(out):
            out.print("m`")
            ast._printOn(out)
            out.print("`")

        to _conformTo(guard):
            if ([Ast, Pattern, Expr, Noun, NamePattern].contains(guard)):
                return ast

        to substitute(values):
            return makeM(ast.transform(makeQuasiAstTransformer(values)), false)


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

def makeQuasiTokenChain(template) as DeepFrozen:
    var i := -1
    var current := makeMonteLexer("", "m``")
    var lex := current
    var j := 0
    def counters := [VALUE_HOLE => -1, PATTERN_HOLE => -1].diverge()
    return object chainer:
        to _makeIterator():
            return chainer

        to valueHole():
           return VALUE_HOLE

        to patternHole():
           return PATTERN_HOLE

        to getSyntaxError():
            return current.getSyntaxError()

        to next(ej):
            if (i >= template.size()):
                throw.eject(ej, null)
            j += 1
            if (current == null):
                if (template[i] == VALUE_HOLE || template[i] == PATTERN_HOLE):
                    def hol := template[i]
                    i += 1
                    return [j, [hol, counters[hol] += 1, null]]
                else:
                    current := lex.lexerForNextChunk(template[i])._makeIterator()
                    lex := current
            escape e:
                def t := current.next(e)[1]
                return [j, t]
            catch z:
                i += 1
                current := null
                return chainer.next(ej)

object m__quasiParser as DeepFrozen:
    "A quasiparser for the Monte programming language.

     This object will parse any Monte expression and return an opaque
     value. In the near future, this object will instead return a translucent
     view into a Monte compiler and optimizer."

    to getAstBuilder():
        return astBuilder

    to valueHole(_):
       return VALUE_HOLE

    to patternHole(_):
       return PATTERN_HOLE

    to valueMaker(template):
        def chain := makeQuasiTokenChain(template)
        def qast := parseExpression(chain, astBuilder, throw)
        return makeM(qast, false)

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
