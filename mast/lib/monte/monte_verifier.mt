import "unittest" =~ [=> unittest]
exports (findUndefinedNames, findUnusedNames)

def Ast :DeepFrozen := ::"m``".getAstBuilder().getAstGuard()
def Noun :DeepFrozen := ::"m``".getAstBuilder().getNounGuard()

def findUndefinedNames(expr, outers) as DeepFrozen:
    def outerNames := [for `&&@name` in (outers.getKeys()) name].asSet()
    def ss := expr.getStaticScope()
    def namesUsed := ss.namesUsed().asSet()
    def offenders := namesUsed &! outerNames
    if (offenders.size() == 0):
        # all good, only names closed over are outers
        return []
    def results := [].diverge()
    def stack := [].diverge()
    def descendInto(item):
        for a in (item._uncall()[2]):
            switch (a):
                match _ :Ast:
                    stack.push(a)
                match _ :List[Ast]:
                    stack.extend(a)
                match _:
                    null
    descendInto(expr)
    while (stack.size() > 0):
        def item := stack.pop()
        def names := item.getStaticScope().namesUsed().asSet()
        if ((offenders & names).size() > 0):
            if (["NounExpr", "SlotExpr", "BindingExpr"].contains(item.getNodeName())):
                results.push(item)
            descendInto(item)
    return results

def leaves :Set[Str] := [
    "BindingExpr",
    "LiteralExpr",
    "MetaContextExpr",
    "MetaStateExpr",
    "NounExpr",
    "SlotExpr",
    "QuasiText",
    "IgnorePattern",
].asSet()

def flattenList(l :List[List]) :List as DeepFrozen:
    var rv := []
    for x in (l) { rv += x }
    return rv

def optional(l :NullOk[List]) :List as DeepFrozen:
    return if (l == null) { [] } else { l }

def filterNouns(l :List[Noun], s :Set[Str]) :List[Noun] as DeepFrozen:
    return [for noun in (l) ? (!s.contains(noun.getName())) noun]

def usedSet(node) :Set[Str] as DeepFrozen:
    return if (node == null) {
        [].asSet()
    } else {
        node.getStaticScope().namesUsed()
    }

def findUnusedNames(expr) :List[Noun] as DeepFrozen:
    "
    Find names in `expr` which are not used.

    To indicate that a name is intentionally unused, simply prefix it with
    '_'.
    "

    def unusedNameFinder(node, _maker, args, _span) :List[Noun]:
        def rv := switch (node.getNodeName()) {
            # Modules
            match =="Module" {
                def [importsList, _exportsList, body] := args
                def incoming := flattenList([for [_, patt] in (importsList) patt])
                def l := filterNouns(incoming, usedSet(node.getBody()))
                def s := {
                    var rv := [].asSet()
                    for ex in (node.getExports()) { rv |= usedSet(ex) }
                    rv
                }
                l + filterNouns(body, s)
            }
            # Sequences.
            match =="SeqExpr" {
                var rv := []
                def exprs := node.getExprs()
                for i => expr in (args[0]) {
                    rv += expr
                    def namesRead := usedSet(exprs[i])
                    rv := filterNouns(rv, namesRead)
                }
                rv
            }
            # Full exprs.
            match n ? (["AndExpr", "OrExpr"].contains(n)) {
                flattenList(args)
            }
            match =="AssignExpr" { flattenList(args) }
            match =="AugAssignExpr" {
                def [_, lvalue, rvalue] := args
                lvalue + rvalue
            }
            match n ? (["BinaryExpr", "CompareExpr"].contains(n)) {
                def [left, _, right] := args
                left + right
            }
            match =="CatchExpr" {
                def [body, patt, catcher] := args
                body + filterNouns(patt + catcher, usedSet(node.getCatcher()))
            }
            match =="CoerceExpr" {
                def [specimen, guard] := args
                specimen + optional(guard)
            }
            match =="CurryExpr" { args[0] }
            match =="DefExpr" {
                def [pattern, exit_, rhs] := args
                pattern + optional(exit_) + rhs
            }
            match =="EscapeExpr" {
                def [ejPatt, ejBody, catchPatt, catchBody] := args
                def ej := filterNouns(ejPatt + ejBody,
                                      usedSet(node.getBody()))
                if (catchBody != null) {
                    def c := filterNouns(catchPatt + catchBody,
                                         usedSet(node.getCatchBody()))
                    ej + c
                } else {
                    ej
                }
            }
            match =="ExitExpr" { optional(args[1]) }
            match =="FinallyExpr" { flattenList(args) }
            match =="ForExpr" {
                def [iterable, key, value, body, catchPatt, catchBody] := args
                def l := filterNouns(iterable + optional(key) + value + body,
                                     usedSet(node.getBody()))
                def c := if (catchBody != null) {
                    filterNouns(catchPatt + catchBody,
                                usedSet(node.getCatchBody()))
                } else { [] }
                l + c
            }
            match =="ForwardExpr" { args[0] }
            match n ? (["FunCallExpr", "FunSendExpr"].contains(n)) {
                def [receiver, arguments, namedArgs] := args
                receiver + flattenList(arguments) + flattenList(namedArgs)
            }
            match =="FunctionExpr" {
                def [patts, namedPatts, body] := args
                filterNouns(flattenList(patts) + flattenList(namedPatts) + body,
                            usedSet(node.getBody()))
            }
            match =="FunctionInterfaceExpr" { args[1] }
            match =="GetExpr" {
                def [receiver, indices] := args
                receiver + flattenList(indices)
            }
            match =="HideExpr" { args[0] }
            match =="IfExpr" {
                def [test, consq, alt] := args
                def l := test + consq + optional(alt)
                var namesRead := usedSet(node.getThen())
                if (alt != null) { namesRead |= usedSet(node.getElse()) }
                filterNouns(l, namesRead)
            }
            match =="InterfaceExpr" { args[1] }
            match n ? (["ListExpr", "MapExpr"].contains(n)) {
                flattenList(args[0])
            }
            match =="ListComprehensionExpr" {
                def [iterable, filter, key, value, body] := args
                def l := iterable + optional(filter) + optional(key) + value
                def used := (usedSet(node.getFilter()) |
                             usedSet(node.getBody()))
                filterNouns(l + body, used)
            }
            match =="MapComprehensionExpr" {
                def [iterable, filter, key, value, bodyk, bodyv] := args
                def l := iterable + optional(filter) + optional(key) + value
                def used := (usedSet(node.getFilter()) |
                             usedSet(node.getBodyKey()) |
                             usedSet(node.getBodyValue()))
                filterNouns(l + bodyk + bodyv, used)
            }
            match =="MapExprAssoc" {
                def [key, value] := args
                key + value
            }
            match =="MapExprExport" { args[0] }
            match n ? (["MatchBindExpr", "MismatchExpr"].contains(n)) {
                flattenList(args)
            }
            match =="MessageDesc" {
                def [_, _, params, namedParams, guard] := args
                flattenList(params + namedParams) + optional(guard)
            }
            match n ? (["MethodCallExpr", "SendExpr"].contains(n)) {
                def [receiver, _, arguments, namedArgs] := args
                receiver + flattenList(arguments) + flattenList(namedArgs)
            }
            match =="ParamDesc" { optional(args[1]) }
            match =="SwitchExpr" {
                def [specimen, matchers] := args
                def s := {
                    var rv := [].asSet()
                    for matcher in (node.getMatchers()) {
                        rv |= usedSet(matcher)
                    }
                    rv
                }
                filterNouns(specimen + flattenList(matchers), s)
            }
            match =="PrefixExpr" { args[1] }
            match n ? (["QuasiExprHole", "QuasiPatternHole"].contains(n)) {
                args[0]
            }
            match n ? (["QuasiParserExpr", "QuasiParserPattern"].contains(n)) {
                def [_, quasis] := args
                flattenList(quasis)
            }
            match =="RangeExpr" {
                def [left, _, right] := args
                left + right
            }
            match =="SameExpr" {
                def [left, right, _] := args
                left + right
            }
            match =="TryExpr" { flattenList(args) }
            match =="VerbAssignExpr" {
                def [_, lvalue, rvalues] := args
                lvalue + flattenList(rvalues)
            }
            match =="WhenExpr" {
                def [arguments, body, catchers, finallyBlock] := args
                def l := filterNouns(flattenList(arguments) + body,
                                     usedSet(node.getBody()))
                l + flattenList(catchers) + optional(finallyBlock)
            }
            match =="WhileExpr" {
                def [test, body, catcher] := args
                def l := filterNouns(test + body, usedSet(node.getBody()))
                l + optional(catcher)
            }
            # Named arguments.
            match =="NamedArg" { flattenList(args) }
            match =="NamedArgExport" { args[0] }
            match =="NamedParam" { args[1] }
            match =="NamedParamImport" { args[0] }
            # Script pieces.
            match =="FunctionScript" {
                def [patts, namedPatts, guard, body] := args
                def l := flattenList(patts) + flattenList(namedPatts) + body
                optional(guard) + filterNouns(l, usedSet(node.getBody()))
            }
            match n ? (["Matcher", "Catcher"].contains(n)) {
                def [patt, body] := args
                filterNouns(patt + body, usedSet(node.getBody()))
            }
            match =="ObjectExpr" {
                # Ignore object names, for `return object obj ...`
                # XXX this logic should be tightened up to only occur in
                # ExitExprs and FunctionExprs.
                def [_, _name, asExpr, auditors, script] := args
                optional(asExpr) + flattenList(auditors) + script
            }
            match =="Script" {
                def [extend, methods, matchers] := args
                optional(extend) + flattenList(methods) + flattenList(matchers)
            }
            match n ? (["Method", "To"].contains(n)) {
                def [_, _, patts, namedPatts, guard, _body] := args
                def l := (flattenList(patts) + flattenList(namedPatts) +
                          optional(guard))
                def namesRead := usedSet(node.getBody())
                filterNouns(l, namesRead)
            }
            # Patterns.
            match n ? (["FinalPattern", "SlotPattern",
                        "VarPattern"].contains(n)) {
                def noun := node.getNoun()
                if (noun.getName().startsWith("_")) {
                    optional(args[1])
                } else { [noun] + optional(args[1]) }
            }
            match n ? (["ListPattern", "MapPattern"].contains(n)) {
                def [patts, tail] := args
                def ps := flattenList(patts)
                ps + optional(tail)
            }
            match =="BindPattern" { optional(args[1]) }
            match =="BindingPattern" { args[0] }
            match =="MapPatternAssoc" {
                def [key, value, default] := args
                key + value + optional(default)
            }
            match =="MapPatternImport" {
                def [patt, default] := args
                patt + optional(default)
            }
            match =="SamePattern" { args[0] }
            match =="SuchThatPattern" {
                def [patt, ex] := args
                filterNouns(patt + ex, usedSet(node.getExpr()))
            }
            match =="ViaPattern" { flattenList(args) }
            # Empty leaves which can't contain anything interesting.
            match leaf ? (leaves.contains(leaf)) { [] }
            match nodeName { throw(`Unsupported node $nodeName $node`) }
        }
        return rv
    return expr.transform(unusedNameFinder)

def testUnusedDef(assert):
    assert.equal(findUnusedNames(m`def x := 42; "asdf"`).size(), 1)

def testUsedSuchThat(assert):
    assert.equal(findUnusedNames(m`fn n ? (n) { 42 }`).size(), 0)

def testUsedExtends(assert):
    assert.equal(findUnusedNames(m`fn f { object g extends f {} }`).size(), 0)

def testUsedVarAugAssign(assert):
    assert.equal(findUnusedNames(m`var x := 0; fn { x += 1 }`).size(), 0)

def testUsedVarAssign(assert):
    assert.equal(findUnusedNames(m`var x := 0; fn { x := 1 }`).size(), 0)

unittest([
    testUnusedDef,
    testUsedSuchThat,
    testUsedExtends,
    testUsedVarAugAssign,
    testUsedVarAssign,
])
