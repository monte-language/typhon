imports => unittest := null
exports (main, inference)
"Type inference for Monte."

def bench(_, _) as DeepFrozen:
    null

def [=> makePureDrain :DeepFrozen] | _ := import("lib/tubes/pureDrain")
def [=> makeUTF8EncodePump :DeepFrozen,
     => makeUTF8DecodePump :DeepFrozen] | _ := import.script("lib/tubes/utf8")
def [=> makePumpTube :DeepFrozen] | _ := import.script("lib/tubes/pumpTube")
def [=> parseModule :DeepFrozen] | _ := import.script("lib/monte/monte_parser")
def [=> makeMonteLexer :DeepFrozen] | _ := import.script("lib/monte/monte_lexer")

def Expr :DeepFrozen := astBuilder.getExprGuard()
def Patt :DeepFrozen := astBuilder.getPatternGuard()

def assigning(rhs, lhs) :Bool as DeepFrozen:
    "Consider whether the `rhs` can be assigned to the `lhs`."

    if (lhs == Any):
        # Top.
        return true

    if (lhs.supersetOf(rhs)):
        return true

    traceln(`Couldn't assign $rhs to $lhs`)
    return false

def shouldHaveMethod(specimen, verb, arity) as DeepFrozen:
    "Check whether a type has a method."

    for meth in specimen.getMethods():
        if (meth.getVerb() == verb && meth.getArity() == arity):
            return
    traceln(`$specimen doesn't have method $verb/$arity`)

def reifyGuard(expr) as DeepFrozen:
    if (expr.getNodeName() == "NounExpr"):
        def &&rv := safeScope.fetch(`&&${expr.getName()}`, fn {&&Any})
        return rv
    return Any


object inference as DeepFrozen:
    to inferPatt(specimen, patt :Patt, var context :Map):
        "Infer the type of a pattern and its specimen."

        return switch (patt.getNodeName()):
            match =="VarPattern":
                def noun :Str := patt.getNoun().getName()
                def g := reifyGuard(patt.getGuard())
                context | [noun => g]
            match name:
                traceln(`Couldn't infer anything about $name`)
                context

    to inferType(expr :Expr, var context :Map):
        "Infer the type of an expression."

        return switch (expr.getNodeName()):
            match =="AugAssignExpr":
                def [rhs, c] := inference.inferType(expr.getRvalue(), context)
                def [lhs, _] := inference.inferType(expr.getLvalue(), context)
                shouldHaveMethod(lhs, expr.getOpName(), 1)
                [rhs, c]
            match =="BinaryExpr":
                def [lhs, c] := inference.inferType(expr.getLeft(), context)
                def [rhs, c2] := inference.inferType(expr.getRight(), c)
                shouldHaveMethod(lhs, expr.getOpName(), 1)
                # XXX don't have method rv guards yet
                [Any, c2]
            match =="DefExpr":
                def [rhs, c] := inference.inferType(expr.getExpr(), context)
                context := inference.inferPatt(rhs, expr.getPattern(), c)
                [rhs, context]
            match =="ForExpr":
                def [iterable, c] := inference.inferType(expr.getIterable(),
                                                         context)
                shouldHaveMethod(iterable, "_makeIterator", 0)
                # XXX key and value
                inference.inferType(expr.getBody(), c)
                [Void, context]
            match =="FunCallExpr":
                def [receiver, c] := inference.inferType(expr.getReceiver(),
                                                         context)
                # XXX punting
                shouldHaveMethod(receiver, "run", expr.getArgs().size())
                # XXX don't have function rv guards yet
                [Any, context]
            match =="LiteralExpr":
                switch (expr.getValue()) {
                    match _ :Bool {[Bool, context]}
                    match _ :Char {[Char, context]}
                    match _ :Double {[Double, context]}
                    match _ :Int {[Int, context]}
                    match _ :Str {[Str, context]}
                    match l {
                        traceln(`Strange literal ${M.toQuote(l)}`)
                        [Any, context]
                    }
                }
            match =="NounExpr":
                def noun :Str := expr.getName()
                def notFound():
                    traceln(`Undefined name $noun`)
                    return Any
                [context.fetch(noun, notFound), context]
            match =="RangeExpr":
                def [left, c] := inference.inferType(expr.getLeft(), context)
                context := c
                def [right, c2] := inference.inferType(expr.getRight(),
                                                       context)
                context := c2
                if (left != right):
                    traceln(`Range expr range type varies from $left to $right`)
                # XXX hax
                def range := switch (left) {
                    match ==Char {('0'..'1')._getAllegedInterface()}
                    match ==Int {(0..1)._getAllegedInterface()}
                    match _ {Any}
                }
                [range, context]
            match =="SeqExpr":
                var rv := Any
                for subExpr in expr.getExprs():
                    def [t, c] := inference.inferType(subExpr, context)
                    rv := t
                    context := c
                [rv, context]
            match name:
                traceln(`Couldn't infer anything about $name`)
                [Any, context]

def testInferLiteral(assert):
    assert.equal(inference.inferType(m`42`, [].asMap()), [Int, [].asMap()])

if (unittest != null):
    unittest([
        testInferLiteral,
    ])

def spongeFile(resource) as DeepFrozen:
    def fileFount := resource.openFount()
    def utf8Fount := fileFount<-flowTo(makePumpTube(makeUTF8DecodePump()))
    def pureDrain := makePureDrain()
    utf8Fount<-flowTo(pureDrain)
    return pureDrain.promisedItems()

def main(=> currentProcess, => makeFileResource, => makeStdOut) as DeepFrozen:
    def path := currentProcess.getArguments().last()

    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout.flowTo(makeStdOut())
    def p := spongeFile(makeFileResource(path))
    return when (p) ->
        def tree := escape ej {
            parseModule(makeMonteLexer("".join(p), path), astBuilder, ej)
        } catch parseErrorMsg {
            stdout.receive(`Syntax error in $path:$\n`)
            stdout.receive(parseErrorMsg)
            1
        }
        def [type, context] := inference.inferType(tree, [].asMap())
        stdout.receive(`Inferred type: $type$\n`)
        0
