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
            out.print(`<context locals=${frameStack[0].getKeys()}>`)

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
            return [[ejected, ex.isPossible()], makeContext(frameStack, ejs, exState)]

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

def stage(ast, var context) :Pair as DeepFrozen:
    if (ast == null):
        return [null, context]

    def s(expr):
        def [rv, c] := stage(expr, context)
        context := c
        return rv

    return switch (ast.getNodeName()) {
        match =="SeqExpr" {
            def exprs := [].diverge()
            var final := m`null`
            def removables := ["LiteralExpr", "NounExpr", "BindingExpr"]
            for expr in (ast.getExprs()) {
                if (!removables.contains(final.getNodeName())) {
                    exprs.push(final)
                }
                final := s(expr)
            }
            exprs.push(final)
            def rv := switch (exprs.snapshot()) {
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
            [astBuilder.AssignExpr(ast.getLvalue(), rhs, ast.getSpan()),
             context]
        }
        match =="HideExpr" {
            context pushFrame= ()
            def body := s(ast.getBody())
            context := context.popFrame()[1]
            # Check the scope to see if any names were defined within this
            # block. If not, then we don't have to keep hiding.
            def sw := astBuilder.makeScopeWalker()
            def ss := sw.getStaticScope(body)
            def rv := if (ss.outNames().isEmpty()) { body } else {
                astBuilder.HideExpr(body, ast.getSpan())
            }
            [rv, context]
        }
        match =="EscapeExpr" {
            context pushFrame= ()
            def ejPatt := ast.getEjectorPattern()
            def [token, c1] := context.freshEjector(ejPatt.getNoun().getName())
            context := c1
            var body := s(ast.getBody())
            def [[ejected :Bool, isPossible :Bool], c2] := context.finishEjector(token)
            traceln(`ejected $ejected (possible $isPossible) from context $context`)
            traceln(`did body $body`)
            context := c2.popFrame()[1]
            var catcher := ast.getCatchBody()
            traceln(`doing catcher $catcher`)
            var catchPatt := ast.getCatchPattern()
            # If we definitely ejected, and there's a catcher, then we must
            # rebuild the body to have the catcher's code alongside it.
            if (ejected && catcher != null) {
                context pushFrame= ()
                # context matchBind= (catchPatt, body, null, stage)
                body := s(m`def $catchPatt := { $body }; $catcher`)
                traceln(`fused body+catcher $body`)
                context := context.popFrame()[1]
            }
            # If it's possible that the ejector could be called, then we have
            # to leave the ejector body in. Otherwise, discard it.
            def rv := if (isPossible) {
                if (catcher != null) {
                    context pushFrame= ()
                    catcher := s(catcher)
                    traceln(`did catcher $catcher`)
                    context := context.popFrame()[1]
                }
                astBuilder.EscapeExpr(ejPatt, body, catchPatt,
                                      catcher, ast.getSpan())
            } else { body }
            [rv, context]
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
        x + y + z
    }`.expand()
    traceln(stage(testcase, emptyContext))
    return 0
