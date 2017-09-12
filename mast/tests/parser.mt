import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseExpression, => parsePattern, => parseModule]
import "fun/termParser" =~ [=> ::"term``"]
import "unittest" =~ [=> unittest]
exports ()

def astFromTerm(t):
    if ((def data := t.getData()) != null):
        return data
    switch (t.getTag().getName()):
        match =="null":
            return null
        match =="true":
            return true
        match =="false":
            return false
        match ==".tuple.":
            return [for a in (t.getArgs()) astFromTerm(a)]
        match _:
            return M.call(
                astBuilder, t.getTag().getName(),
                [for a in (t.getArgs()) astFromTerm(a)] + [null], [].asMap())

def ::"ta``".valueMaker(template):
    return def ta.substitute(vals):
        def t := ::"term``".valueMaker(template).substitute(vals)
        return astFromTerm(t)

def expr(s):
    return parseExpression(makeMonteLexer(s + "\n", "<test>"), astBuilder,
                           throw, throw).canonical()

def pattern(s):
    return parsePattern(makeMonteLexer(s, "<test>"), astBuilder,
                        throw).canonical()

def module(s):
    return parseModule(makeMonteLexer(s + "\n", "<test>"), astBuilder,
                       throw).canonical()

def test_Literal(assert):
    assert.equal(expr("\"foo bar\""), ta`LiteralExpr("foo bar")`)
    assert.equal(expr("'z'"), ta`LiteralExpr('z')`)
    assert.equal(expr("7"), ta`LiteralExpr(7)`)
    assert.equal(expr("(7)"), ta`LiteralExpr(7)`)
    assert.equal(expr("0.5"), ta`LiteralExpr(0.5)`)

def test_Noun(assert):
    assert.equal(expr("foo"), ta`NounExpr("foo")`)
    assert.equal(expr("::\"object\""), ta`NounExpr("object")`)

def test_QuasiliteralExpr(assert):
    assert.equal(expr("`foo`"), ta`QuasiParserExpr(null, [QuasiText("foo")])`)
    assert.equal(expr("bob`foo`"), ta`QuasiParserExpr("bob", [QuasiText("foo")])`)
    assert.equal(expr("bob`foo`` $x baz`"), ta`QuasiParserExpr("bob", [QuasiText("foo`` "), QuasiExprHole(NounExpr("x")), QuasiText(" baz")])`)
    assert.equal(expr("`($x)`"), ta`QuasiParserExpr(null, [QuasiText("("), QuasiExprHole(NounExpr("x")), QuasiText(")")])`)

def test_Hide(assert):
    assert.equal(expr("{}"), ta`HideExpr(SeqExpr([]))`)
    assert.equal(expr("{1}"), ta`HideExpr(LiteralExpr(1))`)

def test_List(assert):
    assert.equal(expr("[]"), ta`ListExpr([])`)
    assert.equal(expr("[a, b]"), ta`ListExpr([NounExpr("a"), NounExpr("b")])`)

def test_Map(assert):
    assert.equal(expr("[k => v, => a]"),
         ta`MapExpr([MapExprAssoc(NounExpr("k"), NounExpr("v")),
                       MapExprExport(NounExpr("a"))])`)
    assert.equal(expr("[=> b, k => v]"),
         ta`MapExpr([MapExprExport(NounExpr("b")),
                       MapExprAssoc(NounExpr("k"), NounExpr("v"))])`)

def test_ListComprehensionExpr(assert):
    assert.equal(expr("[for k => v in (a) ? (b) c]"), ta`ListComprehensionExpr(NounExpr("a"), NounExpr("b"), FinalPattern(NounExpr("k"), null), FinalPattern(NounExpr("v"), null), NounExpr("c"))`)
    assert.equal(expr("[for v in (a) c]"), ta`ListComprehensionExpr(NounExpr("a"), null, null, FinalPattern(NounExpr("v"), null), NounExpr("c"))`)

def test_MapComprehensionExpr(assert):
    assert.equal(expr("[for k => v in (a) ? (b) k1 => v1]"), ta`MapComprehensionExpr(NounExpr("a"), NounExpr("b"), FinalPattern(NounExpr("k"), null), FinalPattern(NounExpr("v"), null), NounExpr("k1"), NounExpr("v1"))`)
    assert.equal(expr("[for v in (a) k1 => v1]"), ta`MapComprehensionExpr(NounExpr("a"), null, null, FinalPattern(NounExpr("v"), null), NounExpr("k1"), NounExpr("v1"))`)

def test_IfExpr(assert):
    assert.equal(expr("if (1) {2} else if (3) {4} else {5}"),
        ta`IfExpr(LiteralExpr(1), LiteralExpr(2), IfExpr(LiteralExpr(3), LiteralExpr(4), LiteralExpr(5)))`)
    assert.equal(expr("if (1) {2} else {3}"), ta`IfExpr(LiteralExpr(1), LiteralExpr(2), LiteralExpr(3))`)
    assert.equal(expr("if (1) {2}"), ta`IfExpr(LiteralExpr(1), LiteralExpr(2), null)`)
    assert.equal(expr("if (1):\n  2\nelse if (3):\n  4\nelse:\n  5"),
        ta`IfExpr(LiteralExpr(1), LiteralExpr(2), IfExpr(LiteralExpr(3), LiteralExpr(4), LiteralExpr(5)))`)
    assert.equal(expr("if (1):\n  2\nelse:\n  3"), ta`IfExpr(LiteralExpr(1), LiteralExpr(2), LiteralExpr(3))`)
    assert.equal(expr("if (1):\n  2"), ta`IfExpr(LiteralExpr(1), LiteralExpr(2), null)`)


def test_EscapeExpr(assert):
    assert.equal(expr("escape e {1} catch p {2}"),
        ta`EscapeExpr(FinalPattern(NounExpr("e"), null), LiteralExpr(1), FinalPattern(NounExpr("p"), null), LiteralExpr(2))`)
    assert.equal(expr("escape e {1}"),
        ta`EscapeExpr(FinalPattern(NounExpr("e"), null), LiteralExpr(1), null, null)`)
    assert.equal(expr("escape e:\n  1\ncatch p:\n  2"),
        ta`EscapeExpr(FinalPattern(NounExpr("e"), null), LiteralExpr(1), FinalPattern(NounExpr("p"), null), LiteralExpr(2))`)
    assert.equal(expr("escape e:\n  1"),
        ta`EscapeExpr(FinalPattern(NounExpr("e"), null), LiteralExpr(1), null, null)`)

def test_ForExpr(assert):
    assert.equal(expr("for v in (foo) {1}"), ta`ForExpr(NounExpr("foo"), null, FinalPattern(NounExpr("v"), null), LiteralExpr(1), null, null)`)
    assert.equal(expr("for k => v in (foo) {1}"), ta`ForExpr(NounExpr("foo"), FinalPattern(NounExpr("k"), null), FinalPattern(NounExpr("v"), null), LiteralExpr(1), null, null)`)
    assert.equal(expr("for k => v in (foo) {1} catch p {2}"), ta`ForExpr(NounExpr("foo"), FinalPattern(NounExpr("k"), null), FinalPattern(NounExpr("v"), null), LiteralExpr(1), FinalPattern(NounExpr("p"), null), LiteralExpr(2))`)
    assert.equal(expr("for v in (foo):\n  1"), ta`ForExpr(NounExpr("foo"), null, FinalPattern(NounExpr("v"), null), LiteralExpr(1), null, null)`)
    assert.equal(expr("for k => v in (foo):\n  1"), ta`ForExpr(NounExpr("foo"), FinalPattern(NounExpr("k"), null), FinalPattern(NounExpr("v"), null), LiteralExpr(1), null, null)`)
    assert.equal(expr("for k => v in (foo):\n  1\ncatch p:\n  2"), ta`ForExpr(NounExpr("foo"), FinalPattern(NounExpr("k"), null), FinalPattern(NounExpr("v"), null), LiteralExpr(1), FinalPattern(NounExpr("p"), null), LiteralExpr(2))`)


def test_FunctionExpr(assert):
    assert.equal(expr("fn {1}"), ta`FunctionExpr([], [], LiteralExpr(1))`)
    assert.equal(expr("fn a, => b {1}"), ta`FunctionExpr([FinalPattern(NounExpr("a"), null)], [NamedParamImport(FinalPattern(NounExpr("b"), null), null)], LiteralExpr(1))`)

def test_SwitchExpr(assert):
    assert.equal(expr("switch (1) {match p {2} match q {3}}"), ta`SwitchExpr(LiteralExpr(1), [Matcher(FinalPattern(NounExpr("p"), null), LiteralExpr(2)), Matcher(FinalPattern(NounExpr("q"), null), LiteralExpr(3))])`)
    assert.equal(expr("switch (1):\n  match p:\n    2\n  match q:\n    3"), ta`SwitchExpr(LiteralExpr(1), [Matcher(FinalPattern(NounExpr("p"), null), LiteralExpr(2)), Matcher(FinalPattern(NounExpr("q"), null), LiteralExpr(3))])`)

def test_TryExpr(assert):
    assert.equal(expr("try {1} catch p {2} catch q {3} finally {4}"),
        ta`FinallyExpr(CatchExpr(CatchExpr(LiteralExpr(1), FinalPattern(NounExpr("p"), null), LiteralExpr(2)), FinalPattern(NounExpr("q"), null), LiteralExpr(3)), LiteralExpr(4))`)
    assert.equal(expr("try {1} finally {2}"),
        ta`FinallyExpr(LiteralExpr(1), LiteralExpr(2))`)
    assert.equal(expr("try {1} catch p {2}"),
        ta`CatchExpr(LiteralExpr(1), FinalPattern(NounExpr("p"), null), LiteralExpr(2))`)
    assert.equal(expr("try:\n  1\ncatch p:\n  2\ncatch q:\n  3\nfinally:\n  4"),
        ta`FinallyExpr(CatchExpr(CatchExpr(LiteralExpr(1), FinalPattern(NounExpr("p"), null), LiteralExpr(2)), FinalPattern(NounExpr("q"), null), LiteralExpr(3)), LiteralExpr(4))`)
    assert.equal(expr("try:\n  1\nfinally:\n  2"),
        ta`FinallyExpr(LiteralExpr(1), LiteralExpr(2))`)
    assert.equal(expr("try:\n  1\ncatch p:\n  2"),
        ta`CatchExpr(LiteralExpr(1), FinalPattern(NounExpr("p"), null), LiteralExpr(2))`)

def test_WhileExpr(assert):
    assert.equal(expr("while (1):\n  2"), ta`WhileExpr(LiteralExpr(1), LiteralExpr(2), null)`)
    assert.equal(expr("while (1):\n  2\ncatch p:\n  3"), ta`WhileExpr(LiteralExpr(1), LiteralExpr(2), Catcher(FinalPattern(NounExpr("p"), null), LiteralExpr(3)))`)

def test_WhenExpr(assert):
    assert.equal(expr("when (1) -> {2}"), ta`WhenExpr([LiteralExpr(1)], LiteralExpr(2), [], null)`)
    assert.equal(expr("when (1, 2) -> {3}"), ta`WhenExpr([LiteralExpr(1), LiteralExpr(2)], LiteralExpr(3), [], null)`)
    assert.equal(expr("when (1) -> {2} catch p {3}"), ta`WhenExpr([LiteralExpr(1)], LiteralExpr(2), [Catcher(FinalPattern(NounExpr("p"), null), LiteralExpr(3))], null)`)
    assert.equal(expr("when (1) -> {2} finally {3}"), ta`WhenExpr([LiteralExpr(1)], LiteralExpr(2), [], LiteralExpr(3))`)
    assert.equal(expr("when (1) -> {2} catch p {3} finally {4}"), ta`WhenExpr([LiteralExpr(1)], LiteralExpr(2), [Catcher(FinalPattern(NounExpr("p"), null), LiteralExpr(3))], LiteralExpr(4))`)
    assert.equal(expr("when (1) ->\n  2"), ta`WhenExpr([LiteralExpr(1)], LiteralExpr(2), [], null)`)
    assert.equal(expr("when (1, 2) ->\n  3"), ta`WhenExpr([LiteralExpr(1), LiteralExpr(2)], LiteralExpr(3), [], null)`)
    assert.equal(expr("when (1) ->\n  2\ncatch p:\n  3"), ta`WhenExpr([LiteralExpr(1)], LiteralExpr(2), [Catcher(FinalPattern(NounExpr("p"), null), LiteralExpr(3))], null)`)
    assert.equal(expr("when (1) ->\n  2\nfinally:\n  3"), ta`WhenExpr([LiteralExpr(1)], LiteralExpr(2), [], LiteralExpr(3))`)
    assert.equal(expr("when (1) ->\n  2\ncatch p:\n  3\nfinally:\n  4"), ta`WhenExpr([LiteralExpr(1)], LiteralExpr(2), [Catcher(FinalPattern(NounExpr("p"), null), LiteralExpr(3))], LiteralExpr(4))`)

def test_ObjectExpr(assert):
    assert.equal(expr("object foo {}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(null, [], []))`)
    assert.equal(expr("object _ {}"), ta`ObjectExpr(null, IgnorePattern(null), null, [], Script(null, [], []))`)
    assert.equal(expr("object ::\"object\" {}"), ta`ObjectExpr(null, FinalPattern(NounExpr("object"), null), null, [], Script(null, [], []))`)
    assert.equal(expr("bind foo {}"), ta`ObjectExpr(null, BindPattern(NounExpr("foo"), null), null, [], Script(null, [], []))`)
    assert.equal(expr("object bind foo {}"), ta`ObjectExpr(null, BindPattern(NounExpr("foo"), null), null, [], Script(null, [], []))`)
    assert.equal(expr("object foo { to doA(x, y) :z {0} method blee() {1} to \"object\"() {2} match p {3} match q {4}}"),
        ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(null, [To(null, "doA", [FinalPattern(NounExpr("x"), null), FinalPattern(NounExpr("y"), null)], [], NounExpr("z"), LiteralExpr(0)), Method(null, "blee", [], [], null, LiteralExpr(1)), To(null, "object", [], [], null, LiteralExpr(2))], [Matcher(FinalPattern(NounExpr("p"), null), LiteralExpr(3)), Matcher(FinalPattern(NounExpr("q"), null), LiteralExpr(4))]))`)
    assert.equal(expr("object foo { to doA(x, y, \"a\" => b) :z {0} method blee(=> a := 9) {1} to \"object\"(=> &b, \"c\" => d :Int := 99) {2} match p {3} match q {4}}"),
        ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(null, [To(null, "doA", [FinalPattern(NounExpr("x"), null), FinalPattern(NounExpr("y"), null)], [NamedParam(LiteralExpr("a"), FinalPattern(NounExpr("b"), null), null)], NounExpr("z"), LiteralExpr(0)), Method(null, "blee", [], [NamedParamImport(FinalPattern(NounExpr("a"), null), LiteralExpr(9))], null, LiteralExpr(1)), To(null, "object", [], [NamedParamImport(SlotPattern(NounExpr("b"), null), null), NamedParam(LiteralExpr("c"), FinalPattern(NounExpr("d"), NounExpr("Int")), LiteralExpr(99))], null, LiteralExpr(2))], [Matcher(FinalPattern(NounExpr("p"), null), LiteralExpr(3)), Matcher(FinalPattern(NounExpr("q"), null), LiteralExpr(4))]))`)
    assert.equal(expr("object foo {\"hello\" to blee() {\"yes\"\n1}}"), ta`ObjectExpr("hello", FinalPattern(NounExpr("foo"), null), null, [], Script(null, [To("yes", "blee", [], [], null, LiteralExpr(1))], []))`)
    assert.equal(expr("object foo {to blee() {}}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(null, [To(null, "blee", [], [], null, SeqExpr([]))], []))`)
    assert.equal(expr("object foo {to blee() {\"yes\"}}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(null, [To("yes", "blee", [], [], null, LiteralExpr("yes"))], []))`)
    assert.equal(expr("object foo as A implements B, C {}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), NounExpr("A"), [NounExpr("B"), NounExpr("C")], Script(null, [], []))`)
    assert.equal(expr("object foo extends baz {}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(NounExpr("baz"), [], []))`)

    assert.equal(expr("object foo:\n  pass"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(null, [], []))`)
    assert.equal(expr("object _:\n  pass"), ta`ObjectExpr(null, IgnorePattern(null), null, [], Script(null, [], []))`)
    assert.equal(expr("object ::\"object\":\n  pass"), ta`ObjectExpr(null, FinalPattern(NounExpr("object"), null), null, [], Script(null, [], []))`)
    assert.equal(expr("bind foo:\n  pass"), ta`ObjectExpr(null, BindPattern(NounExpr("foo"), null), null, [], Script(null, [], []))`)
    assert.equal(expr("object bind foo:\n  pass"), ta`ObjectExpr(null, BindPattern(NounExpr("foo"), null), null, [], Script(null, [], []))`)
    assert.equal(expr("object foo:\n  to doA(x, y) :z:\n    0\n  method blee():\n    1\n  to \"object\"():\n    2\n  match p:\n    3\n  match q:\n    4"),
        ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(null, [To(null, "doA", [FinalPattern(NounExpr("x"), null), FinalPattern(NounExpr("y"), null)], [], NounExpr("z"), LiteralExpr(0)), Method(null, "blee", [], [], null, LiteralExpr(1)), To(null, "object", [], [], null, LiteralExpr(2))], [Matcher(FinalPattern(NounExpr("p"), null), LiteralExpr(3)), Matcher(FinalPattern(NounExpr("q"), null), LiteralExpr(4))]))`)
    assert.equal(expr("object foo:\n  \"hello\"\n  to blee():\n    \"yes\"\n    1"), ta`ObjectExpr("hello", FinalPattern(NounExpr("foo"), null), null, [], Script(null, [To("yes", "blee", [], [], null, LiteralExpr(1))], []))`)
    assert.equal(expr("object foo as A implements B, C:\n  pass"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), NounExpr("A"), [NounExpr("B"), NounExpr("C")], Script(null, [], []))`)
    assert.equal(expr("object foo extends baz:\n  pass"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(NounExpr("baz"), [], []))`)

def test_Function(assert):
    assert.equal(expr("def foo() {1}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], FunctionScript("run", [], [], null, LiteralExpr(1)))`)
    assert.equal(expr("def foo.bar() {1}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], FunctionScript("bar", [], [], null, LiteralExpr(1)))`)
    assert.equal(expr("def foo() {}\n"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], FunctionScript("run", [], [], null, SeqExpr([])))`)
    assert.equal(expr("def foo() {\"yes\"}"), ta`ObjectExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], FunctionScript("run", [], [], null, LiteralExpr("yes")))`)
    assert.equal(expr("def foo(a, b) :c {1}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], FunctionScript("run", [FinalPattern(NounExpr("a"), null), FinalPattern(NounExpr("b"), null)], [], NounExpr("c"), LiteralExpr(1)))`)
    assert.equal(expr("def foo():\n  1"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], FunctionScript("run", [], [], null, LiteralExpr(1)))`)
    assert.equal(expr("def foo(a, b) :c:\n  1"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], FunctionScript("run", [FinalPattern(NounExpr("a"), null), FinalPattern(NounExpr("b"), null)], [], NounExpr("c"), LiteralExpr(1)))`)
    assert.equal(expr("def foo.baz() {1}"), ta`ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], FunctionScript("baz", [], [], null, LiteralExpr(1)))`)

def test_Interface(assert):
    assert.equal(expr("interface foo {\"yes\"}"), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [], [])`)
    assert.equal(expr("interface foo extends baz, blee {\"yes\"}"), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [NounExpr("baz"), NounExpr("blee")], [], [])`)
    assert.equal(expr("interface foo implements bar {\"yes\"}"), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [NounExpr("bar")], [])`)
    assert.equal(expr("interface foo extends baz implements boz, bar {}"), ta`InterfaceExpr(null, FinalPattern(NounExpr("foo"), null), null, [NounExpr("baz")], [NounExpr("boz"), NounExpr("bar")], [])`)
    assert.equal(expr("interface foo guards FooStamp extends boz, biz implements bar {}"), ta`InterfaceExpr(null, FinalPattern(NounExpr("foo"), null), FinalPattern(NounExpr("FooStamp"), null), [NounExpr("boz"), NounExpr("biz")], [NounExpr("bar")], [])`)
    assert.equal(expr("interface foo {\"yes\"\nto run(a :int, b :float64) :any}"), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [], [MessageDesc(null, "run", [ParamDesc("a", NounExpr("int")), ParamDesc("b", NounExpr("float64"))], [], NounExpr("any"))])`)
    assert.equal(expr("interface foo {\"yes\"\nto run(a :int, b :float64) :any {\"msg docstring\"}}"), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [], [MessageDesc("msg docstring", "run", [ParamDesc("a", NounExpr("int")), ParamDesc("b", NounExpr("float64"))], [], NounExpr("any"))])`)
    assert.equal(expr("interface foo(a :int, b :float64) :any {\"msg docstring\"}"), ta`FunctionInterfaceExpr("msg docstring", FinalPattern(NounExpr("foo"), null), null, [], [], MessageDesc("msg docstring", "run", [ParamDesc("a", NounExpr("int")), ParamDesc("b", NounExpr("float64"))], [], NounExpr("any")))`)
    assert.equal(expr("interface foo(a :int, b :float64) :any"), ta`FunctionInterfaceExpr(null, FinalPattern(NounExpr("foo"), null), null, [], [], MessageDesc(null, "run", [ParamDesc("a", NounExpr("int")), ParamDesc("b", NounExpr("float64"))], [], NounExpr("any")))`)

    assert.equal(expr("interface foo:\n  \"yes\""), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [], [])`)
    assert.equal(expr("interface foo extends baz, blee:\n  \"yes\""), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [NounExpr("baz"), NounExpr("blee")], [], [])`)
    assert.equal(expr("interface foo implements bar:\n  \"yes\""), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [NounExpr("bar")], [])`)
    assert.equal(expr("interface foo extends baz implements boz, bar:\n  pass"), ta`InterfaceExpr(null, FinalPattern(NounExpr("foo"), null), null, [NounExpr("baz")], [NounExpr("boz"), NounExpr("bar")], [])`)
    assert.equal(expr("interface foo guards FooStamp extends boz, biz implements bar:\n  pass"), ta`InterfaceExpr(null, FinalPattern(NounExpr("foo"), null), FinalPattern(NounExpr("FooStamp"), null), [NounExpr("boz"), NounExpr("biz")], [NounExpr("bar")], [])`)
    assert.equal(expr("interface foo:\n  \"yes\"\n  to run(a :int, b :float64) :any"), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [], [MessageDesc(null, "run", [ParamDesc("a", NounExpr("int")), ParamDesc("b", NounExpr("float64"))], [], NounExpr("any"))])`)
    assert.equal(expr("interface foo:\n  \"yes\"\n  to run(a :int, b :float64, => c :int, => d) :any"), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [], [MessageDesc(null, "run", [ParamDesc("a", NounExpr("int")), ParamDesc("b", NounExpr("float64"))], [ParamDesc("c", NounExpr("int")), ParamDesc("d", null)], NounExpr("any"))])`)
    assert.equal(expr("interface foo:\n  \"yes\"\n  to run(a :int, b :float64) :any:\n    \"msg docstring\""), ta`InterfaceExpr("yes", FinalPattern(NounExpr("foo"), null), null, [], [], [MessageDesc("msg docstring", "run", [ParamDesc("a", NounExpr("int")), ParamDesc("b", NounExpr("float64"))], [], NounExpr("any"))])`)
    assert.equal(expr("interface foo(a :int, b :float64) :any:\n  \"msg docstring\""), ta`FunctionInterfaceExpr("msg docstring", FinalPattern(NounExpr("foo"), null), null, [], [], MessageDesc("msg docstring", "run", [ParamDesc("a", NounExpr("int")), ParamDesc("b", NounExpr("float64"))], [], NounExpr("any")))`)

def test_Call(assert):
    assert.equal(expr("a.b(c, d)"), ta`MethodCallExpr(NounExpr("a"), "b", [NounExpr("c"), NounExpr("d")], [])`)
    assert.equal(expr("a.b(c, d, => e, \"f\" => g)"), ta`MethodCallExpr(NounExpr("a"), "b", [NounExpr("c"), NounExpr("d")], [NamedArgExport(NounExpr("e")), NamedArg(LiteralExpr("f"), NounExpr("g"))])`)
    assert.equal(expr("a.b()"), ta`MethodCallExpr(NounExpr("a"), "b", [], [])`)
    assert.equal(expr("a.b(=> &c)"), ta`MethodCallExpr(NounExpr("a"), "b", [], [NamedArgExport(SlotExpr(NounExpr("c")))])`)
    assert.equal(expr("a.b"), ta`CurryExpr(NounExpr("a"), "b", false)`)
    assert.equal(expr("a.b().c()"), ta`MethodCallExpr(MethodCallExpr(NounExpr("a"), "b", [], []), "c", [], [])`)
    assert.equal(expr("a.\"if\"()"), ta`MethodCallExpr(NounExpr("a"), "if", [], [])`)
    assert.equal(expr("a(b, c)"), ta`FunCallExpr(NounExpr("a"), [NounExpr("b"), NounExpr("c")], [])`)

def test_Send(assert):
    assert.equal(expr("a <- b(c, d)"), ta`SendExpr(NounExpr("a"), "b", [NounExpr("c"), NounExpr("d")], [])`)
    assert.equal(expr("a <- b(c, d, => e, \"f\" => g)"), ta`SendExpr(NounExpr("a"), "b", [NounExpr("c"), NounExpr("d")], [NamedArgExport(NounExpr("e")), NamedArg(LiteralExpr("f"), NounExpr("g"))])`)
    assert.equal(expr("a <- b()"), ta`SendExpr(NounExpr("a"), "b", [], [])`)
    assert.equal(expr("a <- b"), ta`CurryExpr(NounExpr("a"), "b", true)`)
    assert.equal(expr("a <- b() <- c()"), ta`SendExpr(SendExpr(NounExpr("a"), "b", [], []), "c", [], [])`)
    assert.equal(expr("a <- \"if\"()"), ta`SendExpr(NounExpr("a"), "if", [], [])`)
    assert.equal(expr("a <- (b, c)"), ta`FunSendExpr(NounExpr("a"), [NounExpr("b"), NounExpr("c")], [])`)

def test_Get(assert):
    assert.equal(expr("a[b, c]"), ta`GetExpr(NounExpr("a"), [NounExpr("b"), NounExpr("c")])`)
    assert.equal(expr("a[]"), ta`GetExpr(NounExpr("a"), [])`)
    assert.equal(expr("a.b()[c].d()"), ta`MethodCallExpr(GetExpr(MethodCallExpr(NounExpr("a"), "b", [], []), [NounExpr("c")]), "d", [], [])`)

def test_Meta(assert):
    assert.equal(expr("meta.context()"), ta`MetaContextExpr()`)
    assert.equal(expr("meta.getState()"), ta`MetaStateExpr()`)

def test_Def(assert):
    assert.equal(expr("def a := b"), ta`DefExpr(FinalPattern(NounExpr("a"), null), null, NounExpr("b"))`)
    assert.equal(expr("def a exit b := c"), ta`DefExpr(FinalPattern(NounExpr("a"), null), NounExpr("b"), NounExpr("c"))`)
    assert.equal(expr("var a := b"), ta`DefExpr(VarPattern(NounExpr("a"), null), null, NounExpr("b"))`)
    assert.equal(expr("bind a := b"), ta`DefExpr(BindPattern(NounExpr("a"), null), null, NounExpr("b"))`)
    assert.equal(expr("bind a :Foo := b"), ta`DefExpr(BindPattern(NounExpr("a"), NounExpr("Foo")), null, NounExpr("b"))`)

def test_Assign(assert):
    assert.equal(expr("a := b"), ta`AssignExpr(NounExpr("a"), NounExpr("b"))`)
    assert.equal(expr("a[b] := c"), ta`AssignExpr(GetExpr(NounExpr("a"), [NounExpr("b")]), NounExpr("c"))`)
    assert.equal(expr("a foo= (b)"), ta`VerbAssignExpr("foo", NounExpr("a"), [NounExpr("b")])`)
    assert.equal(expr("a += b"), ta`AugAssignExpr("+", NounExpr("a"), NounExpr("b"))`)

def test_Prefix(assert):
    assert.equal(expr("-3"), ta`PrefixExpr("-", LiteralExpr(3))`)
    assert.equal(expr("!foo.baz()"), ta`PrefixExpr("!", MethodCallExpr(NounExpr("foo"), "baz", [], []))`)
    assert.equal(expr("~foo.baz()"), ta`PrefixExpr("~", MethodCallExpr(NounExpr("foo"), "baz", [], []))`)
    assert.equal(expr("&&foo"), ta`BindingExpr(NounExpr("foo"))`)
    assert.equal(expr("&foo"), ta`SlotExpr(NounExpr("foo"))`)

def test_Coerce(assert):
    assert.equal(expr("foo :baz"), ta`CoerceExpr(NounExpr("foo"), NounExpr("baz"))`)

def test_Infix(assert):
    assert.equal(expr("x ** -y"), ta`BinaryExpr(NounExpr("x"), "**", PrefixExpr("-", NounExpr("y")))`)
    assert.equal(expr("x * y"), ta`BinaryExpr(NounExpr("x"), "*", NounExpr("y"))`)
    assert.equal(expr("x / y"), ta`BinaryExpr(NounExpr("x"), "/", NounExpr("y"))`)
    assert.equal(expr("x // y"), ta`BinaryExpr(NounExpr("x"), "//", NounExpr("y"))`)
    assert.equal(expr("x % y"), ta`BinaryExpr(NounExpr("x"), "%", NounExpr("y"))`)
    assert.equal(expr("x + y"), ta`BinaryExpr(NounExpr("x"), "+", NounExpr("y"))`)
    assert.equal(expr("(x + y) + z"), ta`BinaryExpr(BinaryExpr(NounExpr("x"), "+", NounExpr("y")), "+", NounExpr("z"))`)
    assert.equal(expr("x - y"), ta`BinaryExpr(NounExpr("x"), "-", NounExpr("y"))`)
    assert.equal(expr("x - y + z"), ta`BinaryExpr(BinaryExpr(NounExpr("x"), "-", NounExpr("y")), "+", NounExpr("z"))`)
    assert.equal(expr("x..y"), ta`RangeExpr(NounExpr("x"), "..", NounExpr("y"))`)
    assert.equal(expr("x..!y"), ta`RangeExpr(NounExpr("x"), "..!", NounExpr("y"))`)
    assert.equal(expr("x < y"), ta`CompareExpr(NounExpr("x"), "<", NounExpr("y"))`)
    assert.equal(expr("x <= y"), ta`CompareExpr(NounExpr("x"), "<=", NounExpr("y"))`)
    assert.equal(expr("x <=> y"), ta`CompareExpr(NounExpr("x"), "<=>", NounExpr("y"))`)
    assert.equal(expr("x >= y"), ta`CompareExpr(NounExpr("x"), ">=", NounExpr("y"))`)
    assert.equal(expr("x > y"), ta`CompareExpr(NounExpr("x"), ">", NounExpr("y"))`)
    assert.equal(expr("x << y"), ta`BinaryExpr(NounExpr("x"), "<<", NounExpr("y"))`)
    assert.equal(expr("x >> y"), ta`BinaryExpr(NounExpr("x"), ">>", NounExpr("y"))`)
    assert.equal(expr("x << y >> z"), ta`BinaryExpr(BinaryExpr(NounExpr("x"), "<<", NounExpr("y")), ">>", NounExpr("z"))`)
    assert.equal(expr("x == y"), ta`SameExpr(NounExpr("x"), NounExpr("y"), true)`)
    assert.equal(expr("x != y"), ta`SameExpr(NounExpr("x"), NounExpr("y"), false)`)
    assert.equal(expr("x &! y"), ta`BinaryExpr(NounExpr("x"), "&!", NounExpr("y"))`)
    assert.equal(expr("x ^ y"), ta`BinaryExpr(NounExpr("x"), "^", NounExpr("y"))`)
    assert.equal(expr("x & y"), ta`BinaryExpr(NounExpr("x"), "&", NounExpr("y"))`)
    assert.equal(expr("x & y & z"), ta`BinaryExpr(BinaryExpr(NounExpr("x"), "&", NounExpr("y")), "&", NounExpr("z"))`)
    assert.equal(expr("x | y"), ta`BinaryExpr(NounExpr("x"), "|", NounExpr("y"))`)
    assert.equal(expr("x | y | z"), ta`BinaryExpr(BinaryExpr(NounExpr("x"), "|", NounExpr("y")), "|", NounExpr("z"))`)
    assert.equal(expr("x && y"), ta`AndExpr(NounExpr("x"), NounExpr("y"))`)
    assert.equal(expr("x && y && z"), ta`AndExpr(NounExpr("x"), AndExpr(NounExpr("y"), NounExpr("z")))`)
    assert.equal(expr("x || y"), ta`OrExpr(NounExpr("x"), NounExpr("y"))`)
    assert.equal(expr("x || y || z"), ta`OrExpr(NounExpr("x"), OrExpr(NounExpr("y"), NounExpr("z")))`)
    assert.equal(expr("x =~ y"), ta`MatchBindExpr(NounExpr("x"), FinalPattern(NounExpr("y"), null))`)
    assert.equal(expr("x && y || z"),  expr("(x && y) || z"))
    assert.equal(expr("x || y && z"),  expr("x || (y && z)"))
    assert.equal(expr("x =~ a || y == b && z != c"),
                     expr("(x =~ a) || ((y == b) && (z != c))"))
    assert.equal(expr("x | y > z"),  expr("x | (y > z)"))
    assert.equal(expr("x < y | y > z"),  expr("(x < y) | (y > z)"))
    assert.equal(expr("x & y > z"),  expr("x & (y > z)"))
    assert.equal(expr("x < y & y > z"),  expr("(x < y) & (y > z)"))
    assert.equal(expr("x..y <=> a..!b"),  expr("(x..y) <=> (a..!b)"))
    assert.equal(expr("a << b..y >> z"),  expr("(a << b) .. (y >> z)"))
    assert.equal(expr("x.y() :List[Int] > a..!b"),
                 expr("(x.y() :List[Int]) > a..!b"))
    assert.equal(expr("a + b >> z"),  expr("(a + b) >> z"))
    assert.equal(expr("a >> b + z"),  expr("a >> (b + z)"))
    assert.equal(expr("a + b * c"), expr("a + (b * c)"))
    assert.equal(expr("a - b + c * d"), expr("(a - b) + (c * d)"))
    assert.equal(expr("a / b + c - d"), expr("((a / b) + c) - d"))
    assert.equal(expr("a / b * !c ** ~d"), expr("(a / b) * ((!c) ** (~d))"))

def test_Exits(assert):
    assert.equal(expr("return x + y"), ta`ExitExpr("return", BinaryExpr(NounExpr("x"), "+", NounExpr("y")))`)
    assert.equal(expr("continue x + y"), ta`ExitExpr("continue", BinaryExpr(NounExpr("x"), "+", NounExpr("y")))`)
    assert.equal(expr("break x + y"), ta`ExitExpr("break", BinaryExpr(NounExpr("x"), "+", NounExpr("y")))`)
    assert.equal(expr("return(x + y)"), ta`ExitExpr("return", BinaryExpr(NounExpr("x"), "+", NounExpr("y")))`)
    assert.equal(expr("continue(x + y)"), ta`ExitExpr("continue", BinaryExpr(NounExpr("x"), "+", NounExpr("y")))`)
    assert.equal(expr("break(x + y)"), ta`ExitExpr("break", BinaryExpr(NounExpr("x"), "+", NounExpr("y")))`)
    assert.equal(expr("return()"), ta`ExitExpr("return", null)`)
    assert.equal(expr("continue()"), ta`ExitExpr("continue", null)`)
    assert.equal(expr("break()"), ta`ExitExpr("break", null)`)
    assert.equal(expr("return"), ta`ExitExpr("return", null)`)
    assert.equal(expr("continue"), ta`ExitExpr("continue", null)`)
    assert.equal(expr("break"), ta`ExitExpr("break", null)`)

    # The bareword nature of ExitExpr means that it sometimes clashes with
    # surrounding/trailing tags.
    assert.equal(expr("if (true) { break }"),
                 ta`IfExpr(NounExpr("true"), ExitExpr("break", null), null)`)

def test_IgnorePattern(assert):
    assert.equal(pattern("_"), ta`IgnorePattern(null)`)
    assert.equal(pattern("_ :Int"), ta`IgnorePattern(NounExpr("Int"))`)
    assert.equal(pattern("_ :(1)"), ta`IgnorePattern(LiteralExpr(1))`)

def test_FinalPattern(assert):
    assert.equal(pattern("foo"), ta`FinalPattern(NounExpr("foo"), null)`)
    assert.equal(pattern("foo :Int"), ta`FinalPattern(NounExpr("foo"), NounExpr("Int"))`)
    assert.equal(pattern("foo :(1)"), ta`FinalPattern(NounExpr("foo"), LiteralExpr(1))`)
    assert.equal(pattern("::\"foo baz\""), ta`FinalPattern(NounExpr("foo baz"), null)`)
    assert.equal(pattern("::\"foo baz\" :Int"), ta`FinalPattern(NounExpr("foo baz"), NounExpr("Int"))`)
    assert.equal(pattern("::\"foo baz\" :(1)"), ta`FinalPattern(NounExpr("foo baz"), LiteralExpr(1))`)

def test_SlotPattern(assert):
    assert.equal(pattern("&foo"), ta`SlotPattern(NounExpr("foo"), null)`)
    assert.equal(pattern("&foo :Int"), ta`SlotPattern(NounExpr("foo"), NounExpr("Int"))`)
    assert.equal(pattern("&foo :(1)"), ta`SlotPattern(NounExpr("foo"), LiteralExpr(1))`)
    assert.equal(pattern("&::\"foo baz\""), ta`SlotPattern(NounExpr("foo baz"), null)`)
    assert.equal(pattern("&::\"foo baz\" :Int"), ta`SlotPattern(NounExpr("foo baz"), NounExpr("Int"))`)
    assert.equal(pattern("&::\"foo baz\" :(1)"), ta`SlotPattern(NounExpr("foo baz"), LiteralExpr(1))`)

def test_VarPattern(assert):
    assert.equal(pattern("var foo"), ta`VarPattern(NounExpr("foo"), null)`)
    assert.equal(pattern("var foo :Int"), ta`VarPattern(NounExpr("foo"), NounExpr("Int"))`)
    assert.equal(pattern("var foo :(1)"), ta`VarPattern(NounExpr("foo"), LiteralExpr(1))`)
    assert.equal(pattern("var ::\"foo baz\""), ta`VarPattern(NounExpr("foo baz"), null)`)
    assert.equal(pattern("var ::\"foo baz\" :Int"), ta`VarPattern(NounExpr("foo baz"), NounExpr("Int"))`)
    assert.equal(pattern("var ::\"foo baz\" :(1)"), ta`VarPattern(NounExpr("foo baz"), LiteralExpr(1))`)

def test_BindPattern(assert):
    assert.equal(pattern("bind foo"), ta`BindPattern(NounExpr("foo"), null)`)
    assert.equal(pattern("bind ::\"foo baz\""), ta`BindPattern(NounExpr("foo baz"), null)`)
    assert.equal(pattern("bind foo :Baz"), ta`BindPattern(NounExpr("foo"), NounExpr("Baz"))`)

def test_BindingPattern(assert):
    assert.equal(pattern("&&foo"), ta`BindingPattern(NounExpr("foo"))`)
    assert.equal(pattern("&&::\"foo baz\""), ta`BindingPattern(NounExpr("foo baz"))`)

def test_SamePattern(assert):
    assert.equal(pattern("==1"), ta`SamePattern(LiteralExpr(1), true)`)
    assert.equal(pattern("==(x)"), ta`SamePattern(NounExpr("x"), true)`)

def test_NotSamePattern(assert):
    assert.equal(pattern("!=1"), ta`SamePattern(LiteralExpr(1), false)`)
    assert.equal(pattern("!=(x)"), ta`SamePattern(NounExpr("x"), false)`)

def test_ViaPattern(assert):
    assert.equal(pattern("via (b) a"), ta`ViaPattern(NounExpr("b"), FinalPattern(NounExpr("a"), null))`)

def test_ListPattern(assert):
    assert.equal(pattern("[]"), ta`ListPattern([], null)`)
    assert.equal(pattern("[a, b]"), ta`ListPattern([FinalPattern(NounExpr("a"), null), FinalPattern(NounExpr("b"), null)], null)`)
    assert.equal(pattern("[a, b] + c"), ta`ListPattern([FinalPattern(NounExpr("a"), null), FinalPattern(NounExpr("b"), null)], FinalPattern(NounExpr("c"), null))`)

def test_MapPattern(assert):
     assert.equal(pattern("[\"k\" => v, (a) => b, => c]"), ta`MapPattern([MapPatternAssoc(LiteralExpr("k"), FinalPattern(NounExpr("v"), null), null), MapPatternAssoc(NounExpr("a"), FinalPattern(NounExpr("b"), null), null), MapPatternImport(FinalPattern(NounExpr("c"), null), null)], null)`)
     assert.equal(pattern("[\"a\" => b := 1] | c"), ta`MapPattern([MapPatternAssoc(LiteralExpr("a"), FinalPattern(NounExpr("b"), null), LiteralExpr(1))], FinalPattern(NounExpr("c"), null))`)
     assert.equal(pattern("[\"k\" => &v, => &&b, => ::\"if\"]"), ta`MapPattern([MapPatternAssoc(LiteralExpr("k"), SlotPattern(NounExpr("v"), null), null), MapPatternImport(BindingPattern(NounExpr("b")), null), MapPatternImport(FinalPattern(NounExpr("if"), null), null)], null)`)

def test_QuasiliteralPattern(assert):
    assert.equal(pattern("`foo`")._uncall(), ta`QuasiParserPattern(null, [QuasiText("foo")])`._uncall())
    assert.equal(pattern("bob`foo`"), ta`QuasiParserPattern("bob", [QuasiText("foo")])`)
    assert.equal(pattern("bob`foo`` $x baz`"), ta`QuasiParserPattern("bob", [QuasiText("foo`` "), QuasiExprHole(NounExpr("x")), QuasiText(" baz")])`)
    assert.equal(pattern("`($x)`"), ta`QuasiParserPattern(null, [QuasiText("("), QuasiExprHole(NounExpr("x")), QuasiText(")")])`)
    assert.equal(pattern("`foo @{w}@x $y${z} baz`"), ta`QuasiParserPattern(null, [QuasiText("foo "), QuasiPatternHole(FinalPattern(NounExpr("w"), null)), QuasiPatternHole(FinalPattern(NounExpr("x"), null)), QuasiText(" "), QuasiExprHole(NounExpr("y")), QuasiExprHole(NounExpr("z")), QuasiText(" baz")])`)

def test_SuchThatPattern(assert):
    assert.equal(pattern("x :y ? (1)"), ta`SuchThatPattern(FinalPattern(NounExpr("x"), NounExpr("y")), LiteralExpr(1))`)

def test_bareModule(assert):
    assert.equal(module("object foo {}"), ta`Module([], [], ObjectExpr(null, FinalPattern(NounExpr("foo"), null), null, [], Script(null, [], [])))`)

def test_moduleExports(assert):
    assert.equal(module("exports (a)\ndef a := 1"), ta`Module([], ["a"], DefExpr(FinalPattern(NounExpr("a"), null), null, LiteralExpr(1)))`)

def test_module(assert):
    assert.equal(module("import \"foo\" =~ foo\nimport \"blee\" =~ [=> a, => b]\nexports (a)\ndef a := 1"), ta`Module([Import("foo", FinalPattern(NounExpr("foo"), null)), Import("blee", MapPattern([MapPatternImport(FinalPattern(NounExpr("a"), null), null), MapPatternImport(FinalPattern(NounExpr("b"), null), null)], IgnorePattern(null)))], [NounExpr("a")], DefExpr(FinalPattern(NounExpr("a"), null), null, LiteralExpr(1)))`)

# def test_holes(assert):
#     assert.equal(quasiMonteParser.valueMaker(["foo(", quasiMonteParser.valueHole(0), ")"]), ta`ValueHoleExpr(0)`)
#     assert.equal(expr("@{2}"), ta`PatternHoleExpr(2)`)
#     assert.equal(pattern("${2}"), ta`ValueHoleExpr(0)`)
#     assert.equal(pattern("@{2}"), ta`PatternHoleExpr(0)`)

unittest([
    test_Literal, test_Noun, test_QuasiliteralExpr, test_Hide, test_Call,
    test_Send, test_Get, test_Meta, test_List, test_Map,
    test_ListComprehensionExpr, test_MapComprehensionExpr, test_IfExpr,
    test_EscapeExpr, test_ForExpr, test_FunctionExpr, test_SwitchExpr,
    test_TryExpr, test_WhileExpr, test_WhenExpr, test_ObjectExpr,
    test_Function, test_Interface, test_Def, test_Assign, test_Prefix,
    test_Coerce, test_Infix, test_Exits, test_IgnorePattern,
    test_FinalPattern, test_VarPattern, test_BindPattern, test_SamePattern,
    test_NotSamePattern, test_SlotPattern, test_BindingPattern,
    test_ViaPattern, test_ListPattern, test_MapPattern,
    test_QuasiliteralPattern, test_SuchThatPattern, test_module,
])
