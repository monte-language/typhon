import "lib/monte/monte_lexer" =~ [=> makeMonteLexer :DeepFrozen]
import "lib/monte/monte_parser" =~ [
    => parseExpression :DeepFrozen,
    => parsePattern :DeepFrozen,
]
import "lib/monte/monte_expander" =~ [=> expand :DeepFrozen]
import "lib/monte/monte_optimizer" =~ [=> optimize :DeepFrozen]
#import "lib/monte/normalizer" =~ [=> normalize :DeepFrozen]
import "boot" =~ [=> TransparentStamp :DeepFrozen]
exports (::"m``", ::"mpatt``", eval)


def [VALUE_HOLE :DeepFrozen,
     PATTERN_HOLE :DeepFrozen] := makeMonteLexer.holes()

def zipList(left :List, right :List) as DeepFrozen:
    if (left.size() != right.size()):
        throw("Can't zip lists of unequal length")
    var i := -1
    return object zip:
        to _makeIterator():
            return zip
        to next(ej):
            i += 1
            if (i == left.size()):
                throw.eject(ej, null)
            return [i, [left[i], right[i]]]

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

def Ast :DeepFrozen := astBuilder.getAstGuard()
def Pattern :DeepFrozen := astBuilder.getPatternGuard()
def Expr :DeepFrozen := astBuilder.getExprGuard()
def NamePattern :DeepFrozen := astBuilder.getNamePatternGuard()
def Noun :DeepFrozen := astBuilder.getNounGuard()

def makeM(ast :Ast, label :Str, isKernel :Bool) as DeepFrozen:
    return object m extends ast implements Selfless, TransparentStamp:
        "An abstract syntax tree in the Monte programming language."

        to _printOn(out):
            out.print(label)
            out.print("`")
            ast._printOn(out)
            out.print("`")

        to _conformTo(guard):
            if ([Ast, Pattern, Expr, Noun, NamePattern].contains(guard)):
                return ast

        to _uncall():
            return [makeM, "run", [ast, label, isKernel], [].asMap()]

        to substitute(values):
            return makeM(ast.transform(makeQuasiAstTransformer(values)),
                         label, false)

        to matchBind(values, specimen :Ast, ej):
            "Walk over the pattern AST and the specimen comparing each node.
            Value holes in the pattern are substituted before comparison.
            Pattern holes are used to collect nodes to return for binding."
            def nextNodePairs := [[ast.canonical(), specimen.canonical()]].diverge()

            def results := [].asMap().diverge()
            while (nextNodePairs.size() != 0):
                def [var patternNode, specimenNode] := nextNodePairs.pop()
                # Is this node a value hole? Replace it before further comparison.
                if (patternNode.getNodeName().startsWith("ValueHole")):
                        patternNode := values[patternNode.getIndex()]
                # Is this node a pattern hole? Collect the specimen's node.
                if (patternNode.getNodeName().startsWith("PatternHole")):
                    results[patternNode.getIndex()] := specimenNode
                    continue
                if (patternNode.getNodeName() != specimenNode.getNodeName()):
                    throw.eject(ej, "<" + patternNode.getNodeName() + "> != <" + specimenNode.getNodeName() ">")
                # Let's look at node contents now.
                def argPairs := zipList(patternNode._uncall()[2],
                                        specimenNode._uncall()[2])
                for [pattArg, specArg] in (argPairs):
                    if (pattArg =~ _ :Ast):
                        if (specArg =~ _ :Ast):
                            nextNodePairs.push([pattArg, specArg])
                        else:
                            throw.eject(ej, "Expected " + pattArg.getNodeName() + " " +
                                        M.toQuote(pattArg) + ", not " + M.toQuote(specArg))
                    # Non-node children might be lists of nodes.
                    else if (pattArg =~ _ :List):
                        if (specArg !~ _ :List):
                            throw.eject(ej, "Expected list, not " + M.toString(specArg))
                        if (pattArg.size() != specArg.size()):
                            throw.eject(ej, "List size mismatch: " + M.toString(pattArg) + " !~ " + M.toString(specArg))
                        nextNodePairs.extend(zipList(pattArg, specArg))
                    # Ensure everything else matches.
                    else:
                        if (pattArg != specArg):
                            throw.eject(ej, "Expected " + M.toQuote(pattArg) +
                                        ", not " + M.toQuote(specArg))
            return [for node in (results.sortKeys().getValues())
                    makeM(node, label, false)]

        to expand():
            "Desugar all non-Kernel-Monte syntax into Kernel-Monte."

            if (isKernel):
                return m

            escape ej:
                return makeM(expand(ast, astBuilder, ej), label, true)
            catch error:
                throw(`Couldn't expand to Kernel-Monte: $error`)

        to mix():
            "Aggressively optimize Kernel-Monte."

            if (!isKernel):
                throw(`Can't optimize unexpanded AST`)

            return makeM(optimize(ast), label, true)

def makeQuasiTokenLexer(template, sourceLabel :Str) as DeepFrozen:
    def source := [].diverge()
    var val := -1
    var patt := -1
    for piece in (template):
        switch (piece):
            match s :Str:
                for c in (s) { source.push(c) }
            match ==VALUE_HOLE:
                source.push([VALUE_HOLE, val += 1, null])
            match ==PATTERN_HOLE:
                source.push([PATTERN_HOLE, patt += 1, null])
    return makeMonteLexer(source.snapshot(), sourceLabel)

object ::"m``" as DeepFrozen:
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
        def lexer := makeQuasiTokenLexer(template, "m``")
        def qast := parseExpression(lexer, astBuilder, throw, throw)
        return makeM(qast, "m", false)

    to matchMaker(template):
        def lexer := makeQuasiTokenLexer(template, "m``")
        def qast := parseExpression(lexer, astBuilder, throw, throw)
        return makeM(qast, "m", false)

    to fromStr(source :Str):
        def tree := parseExpression(makeMonteLexer(source, "m``.fromStr/1"),
                                    astBuilder, throw, throw)
        return makeM(tree, "m", false)

object ::"mpatt``" as DeepFrozen:
    "A quasiparser for the Monte programming language's patterns.

     This object is like m``, but for patterns."

    to getAstBuilder():
        return astBuilder

    to valueHole(_):
       return VALUE_HOLE

    to patternHole(_):
       return PATTERN_HOLE

    to valueMaker(template):
        def lexer := makeQuasiTokenLexer(template, "mpatt``")
        def qast := parsePattern(lexer, astBuilder, throw)
        return makeM(qast, "mpatt", false)

    to matchMaker(template):
        def lexer := makeQuasiTokenLexer(template, "mpatt``")
        def qast := parsePattern(lexer, astBuilder, throw)
        return makeM(qast, "mpatt", false)

    to fromStr(source :Str):
        def tree := parsePattern(makeMonteLexer(source, "mpatt``.fromStr/1"),
                                 astBuilder, throw)
        return makeM(tree, "mpatt", false)


object eval as DeepFrozen:
    "Evaluate Monte source.

     This object respects POLA and grants no privileges whatsoever to
     evaluated code. To grant a safe scope, pass `safeScope`."

    to run(expr, environment, => evaluator := typhonAstEval,
           => filename := "<eval>", => inRepl := false):
        "Evaluate a Monte expression, from source or from m``.

         The expression will be provided only the given environment. No other
         values will be passed in."

        return eval.evalToPair(expr, environment, => filename, => evaluator,
                               => inRepl)[0]

    to evalToPair(expr, environment, => ejPartial := throw,
                  => filename := "<eval>", => evaluator := typhonAstEval,
                  => inRepl := false):
        def fullAst :Expr := if (expr =~ source :Str) {
            parseExpression(makeMonteLexer(source, filename), astBuilder,
                            throw, ejPartial)
        } else {expr}
        def ast := optimize(expand(fullAst, astBuilder, throw))
        def nast := normalize(ast, typhonAstBuilder)
        return evaluator.evalToPair(nast, environment, filename, => inRepl)
