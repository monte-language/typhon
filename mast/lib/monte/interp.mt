import "lib/enum" =~ [=> makeEnum :DeepFrozen]
exports (main)

def [_ExState :DeepFrozen,
    NORMAL :DeepFrozen,
    EJECTING :DeepFrozen,
] := makeEnum(["normal", "ejecting"])

interface EjToken :DeepFrozen {}

def makeEx(name :Str, => token :DeepFrozen, => possible :Bool) :DeepFrozen as DeepFrozen:
    return object ex as DeepFrozen:
        to _printOn(out):
            out.print(`<ex info [possible => $possible]>`)

        to isPossible() :Bool:
            return possible

        to maybeFired() :DeepFrozen:
            return makeEx(name, => token, "possible" => true)

# NB: The frame stack grows to the left, so that the current frame, if any, is
# first in iteration.
def makeContext(frameStack :List[Map[Str, DeepFrozen]],
                ejectors :Map[DeepFrozen, DeepFrozen],
                exState :Pair[DeepFrozen, DeepFrozen]) :DeepFrozen as DeepFrozen:
    return object context as DeepFrozen:
        to _printOn(out):
            out.print(`<context exState=$exState locals=${frameStack[0].getKeys()}>`)

        to isNormal() :Bool:
            return exState[0] == NORMAL

        to pushFrame() :DeepFrozen:
            return makeContext([[].asMap()] + frameStack, ejectors, exState)

        to popFrame() :Pair[Map, DeepFrozen]:
            def [frame] + tail := frameStack
            return [frame, makeContext(tail, ejectors, exState)]

        to freshEjector(name :Str) :Pair[DeepFrozen, DeepFrozen]:
            "Assign a fresh ejector to `name`."
            object ejToken as DeepFrozen implements EjToken {}
            def ex := makeEx(name, "token" => ejToken, "possible" => false)
            def [frame] + tail := frameStack
            return [ejToken, makeContext([frame.with(name, ejToken)] + tail,
                                         ejectors.with(ejToken, ex), exState)]

        to throwEjector(token :DeepFrozen ? (ejectors.contains(token))) :DeepFrozen:
            # In case we get downgraded later, we should mark that we are at
            # least possibly going to throw this ejector, right? Wrong. If we
            # are *definitely* throwing, then we need to preserve the
            # information that we are not in a maybe-firing state, but in an
            # unconditionally-firing state.
            return makeContext(frameStack, ejectors, [EJECTING, token])

        to finishEjector(token :DeepFrozen) :Pair[DeepFrozen, DeepFrozen]:
            "Retire the ejector represented by `token` and get its status."
            def [(token) => ex] | ejs := ejectors
            def [nextState, ejected] := if (exState == [EJECTING, token]) {
                [[NORMAL, null], true]
            } else { [exState, false] }
            return [[ejected, ex.isPossible()],
                    makeContext(frameStack, ejs, nextState)]

        to fetch(name :Str, ej) :DeepFrozen:
            "Do a frame lookup."
            for frame in (frameStack):
                return frame.fetch(name, __continue)
            throw.eject(ej, `context.get/1: Undefined name $name`)

        to assign(name :Str, value):
            "Set `name` to `value` in the current frame."
            def [frame] + tail := frameStack
            return makeContext([frame.with(name, value)] + tail, ejectors,
                               exState)

        to matchBind(patt, specimen, ej, stage) :NullOk[DeepFrozen]:
            "
            Extend this context to contain a matched pattern, or return `null`
            on failure.
            "
            return switch (patt.getNodeName()) {
                match =="FinalPattern" {
                    def [guard, c1] := stage(patt.getGuard(), context)
                    if (guard != null && guard !~ m`null`) {
                        throw.eject(ej, "asdf")
                    }
                    c1.assign(patt.getNoun().getName(), specimen)
                }
                match =="VarPattern" { throw.eject(ej, "nope") }
            }

def emptyContext :DeepFrozen := makeContext([[].asMap()], [].asMap(),
                                            [NORMAL, null])

def unfold.literal(receiver, verb, args, namedArgs, ej) as DeepFrozen:
    def fail():
        throw.eject(ej, `Couldn't unfold literal`)

    def Ast := astBuilder.getAstGuard()

    def lit(specimen, ej):
        def ast :Ast ? (ast.getNodeName() == "LiteralExpr") exit ej := specimen
        return ast.getValue()

    def litExpr(l):
        return astBuilder.LiteralExpr(l, null)

    return switch (receiver):
        match i :Int:
            switch ([verb, args, namedArgs]):
                match [=="add", [via (lit) j :Int], _]:
                    litExpr(i + j)
                match _:
                    fail()
        match s :Str:
            switch ([verb, args, namedArgs]):
                match [=="add", [via (lit) t :Str], _]:
                    litExpr(s + t)
                match _:
                    fail()
        match _:
            fail()

def stage(ast, var context ? (context.isNormal())) :Pair as DeepFrozen:
    if (ast == null):
        return [null, context]

    def s(expr):
        def [rv, c] := stage(expr, context)
        context := c
        return rv

    def push():
        context pushFrame= ()

    def pop():
        context := context.popFrame()[1]

    return switch (ast.getNodeName()) {
        match =="SeqExpr" {
            # Rather than get smart here, we're going to first iterate through
            # the sequence to stage it, and then fix up nested sequences in a
            # second iteration. If we become erroring at any point, then we
            # will propagate that erroring status and stop staging.
            var exprs := [for expr in (ast.getExprs())
                          ? (context.isNormal()) s(expr)]
            def last := if (exprs.isEmpty()) { m`null` } else {
                def rv := exprs.last()
                exprs := exprs.slice(0, exprs.size() - 1)
                rv
            }
            def removables := ["LiteralExpr", "NounExpr", "BindingExpr"]
            def exprStack := exprs.diverge()
            def goodExprs := [].diverge()
            while (!exprStack.isEmpty()) {
                def expr := exprStack.pop()
                def nodeName := expr.getNodeName()
                if (nodeName == "SeqExpr") {
                    for node in (expr.getExprs()) { exprStack.push(node) }
                } else if (!removables.contains(nodeName)) {
                    goodExprs.push(expr)
                }
            }
            def rv := switch (goodExprs.reverse() + [last]) {
                match [x] { x }
                match l { astBuilder.SeqExpr(l, ast.getSpan()) }
            }
            [rv, context]
        }
        match =="DefExpr" {
            def rhs := s(ast.getExpr())
            def ex := s(ast.getExit())
            def patt := ast.getPattern()
            escape ej {
                [rhs, context.matchBind(patt, rhs, ej, stage)]
            } catch _ {
                [astBuilder.DefExpr(patt, ex, rhs, ast.getSpan()), context]
            }
        }
        match =="NounExpr" {
            def rv := escape ej {
                context.fetch(ast.getName(), ej)
            } catch _ { ast }
            [rv, context]
        }
        match =="MethodCallExpr" {
            def receiver := s(ast.getReceiver())
            def verb := ast.getVerb()
            def args := [for arg in (ast.getArgs()) s(arg)]
            def namedArgs := [for namedArg in (ast.getNamedArgs()) s(namedArg)]
            def rv := escape ej {
                if (receiver =~ token :EjToken) {
                    # Check to make sure that our ejector invocation is valid;
                    # we need no named arguments and exactly zero or one
                    # positional arguments.
                    if (!namedArgs.isEmpty()) {
                        throw("Ejector statically called with multiple arguments")
                    }
                    def innerComp := switch (args) {
                        match [] { m`null` }
                        match [v] { v }
                    }
                    context throwEjector= (token)
                    innerComp
                } else if (receiver.getNodeName() == "LiteralExpr") {
                    unfold.literal(receiver.getValue(), verb, args, namedArgs,
                                   ej)
                } else { ej() }
            } catch _ {
                astBuilder.MethodCallExpr(receiver, verb, args, namedArgs,
                                          ast.getSpan())
            }
            [rv, context]
        }
        match =="AssignExpr" {
            def rhs := s(ast.getRvalue())
            [ast.withRvalue(rhs), context]
        }
        match =="HideExpr" {
            push()
            def body := s(ast.getBody())
            pop()
            # Check the scope to see if any names were defined within this
            # block. If not, then we don't have to keep hiding.
            def sw := astBuilder.makeScopeWalker()
            def ss := sw.getStaticScope(body)
            def rv := if (ss.outNames().isEmpty()) { body } else {
                ast.withBody(body)
            }
            [rv, context]
        }
        match =="EscapeExpr" {
            push()
            def ejPatt := ast.getEjectorPattern()
            def [token, c1] := context.freshEjector(ejPatt.getNoun().getName())
            context := c1
            var body := s(ast.getBody())
            def [[ejected :Bool, isPossible :Bool], c2] := context.finishEjector(token)
            context := c2.popFrame()[1]
            var catcher := ast.getCatchBody()
            var catchPatt := ast.getCatchPattern()
            # If we definitely ejected, and there's a catcher, then we must
            # rebuild the body to have the catcher's code alongside it.
            if (ejected && catcher != null) {
                push()
                # context matchBind= (catchPatt, body, null, stage)
                body := s(m`def $catchPatt := { $body }; $catcher`)
                pop()
            }
            # If it's possible that the ejector could be called, then we have
            # to leave the ejector body in. Otherwise, discard it.
            def rv := if (isPossible) {
                if (catcher != null) {
                    push()
                    catcher := s(catcher)
                    pop()
                }
                astBuilder.EscapeExpr(ejPatt, body, catchPatt,
                                      catcher, ast.getSpan())
            } else { body }
            [rv, context]
        }
        match =="ObjectExpr" {
            # XXX as is common in my interps, I'm punting on auditors for now
            # XXX many punt
            def script := ast.getScript()
            def methods := [for m in (script.getMethods()) {
                push()
                def body := s(m.getBody())
                pop()
                m.withBody(body)
            }]
            def matchers := [for m in (script.getMatchers()) {
                push()
                def body := s(m.getBody())
                pop()
                m.withBody(body)
            }]
            def newScript := astBuilder.Script(null, methods, matchers,
                                               ast.getSpan())
            [ast.withScript(newScript), context]
        }
        match _v { [ast, context] }
    }

def main(_argv) as DeepFrozen:
    def testcase := m`{
        def x := 2
        def y := {
            def z := 3
            x + z
        }
        var z := 1
        escape ej {
            def inner := "hello"
            z += 2
            ej(traceln(inner + " world"))
        } catch problem { z *= 2; outer }
        def f(w) { z += x; return w + y }
        x + y + z
    }`.expand()
    traceln(stage(testcase, emptyContext))
    return 0
