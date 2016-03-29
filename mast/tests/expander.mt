import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
import "lib/monte/monte_expander" =~ [=> expand]
import "unittest" =~ [=> unittest]
exports ()

def tests := [].diverge()

def fixedPointSpecimens := [
    "x",
    "x := y",
    "x := y := z",
    "foo.bar(x, y)",
    "def [x, y] := z",
    "def x :y exit z := w",
    "def &&x := y",
    "def via (x) y := z",
    "
    if (x):
        y
    else:
        z",
    "
    if (x):
        y
    else if (z):
        w",
    "
    object x:
        method y():
            z
    ",
    "
    object x:
        match y:
            z
    ",
]

def specimens := [
    ["x[i] := y",
     "
     x.put(i, def ares_1 := y)
     ares_1"],

    ["x[i] := y; ares_1",
     "
     x.put(i, def ares_2 := y)
     ares_2
     ares_1"],

    ["x foo= (y, z)", "x := x.foo(y, z)"],

    ["x[i] foo= (y)",
     "
     def recip_1 := x
     def arg_2 := i
     recip_1.put(arg_2, def ares_3 := recip_1.get(arg_2).foo(y))
     ares_3"],
    ["x[i] += y",
     "
     def recip_1 := x
     def arg_2 := i
     recip_1.put(arg_2, def ares_3 := recip_1.get(arg_2).add(y))
     ares_3"],

    ["x + y",
     "x.add(y)"],

    ["x - y",
     "x.subtract(y)"],

    ["x * y",
     "x.multiply(y)"],

    ["x / y",
     "x.approxDivide(y)"],

    ["x // y",
     "x.floorDivide(y)"],

    ["x % y",
     "x.mod(y)"],

    ["x ** y",
     "x.pow(y)"],

    ["x >> y",
     "x.shiftRight(y)"],

    ["x << y",
     "x.shiftLeft(y)"],

    ["x & y",
     "x.and(y)"],

    ["x | y",
     "x.or(y)"],

    ["x ^ y",
     "x.xor(y)"],

    ["x += y",
     "x := x.add(y)"],

    ["x -= y",
     "x := x.subtract(y)"],

    ["x *= y",
     "x := x.multiply(y)"],

    ["x /= y",
     "x := x.approxDivide(y)"],

    ["x //= y",
     "x := x.floorDivide(y)"],

    ["x %= y",
     "x := x.mod(y)"],

    ["x **= y",
     "x := x.pow(y)"],

    ["x >>= y",
     "x := x.shiftRight(y)"],

    ["x <<= y",
     "x := x.shiftLeft(y)"],

    ["x &= y",
     "x := x.and(y)"],

    ["x |= y",
     "x := x.or(y)"],

    ["x ^= y",
     "x := x.xor(y)"],

    ["!x", "x.not()"],
    ["-x", "x.negate()"],
    ["~x", "x.complement()"],

    ["x < y", "_comparer.lessThan(x, y)"],
    ["x <= y", "_comparer.leq(x, y)"],
    ["x > y", "_comparer.greaterThan(x, y)"],
    ["x >= y", "_comparer.geq(x, y)"],
    ["x <=> y", "_comparer.asBigAs(x, y)"],

    ["x == y", "_equalizer.sameEver(x, y)"],
    ["x != y", "_equalizer.sameEver(x, y).not()"],

    ["x..y", "_makeOrderedSpace.op__thru(x, y)"],
    ["x..!y", "_makeOrderedSpace.op__till(x, y)"],

    ["object foo { method baz(a, => b, => &c := (0), => &&d) {1} }",
     "object foo {method baz(a, \"b\" => b, \"&c\" =>  via (_slotToBinding) &&c := (0), \"&&d\" => &&d) {1}}"],

    ["foo <- bar(x, y)",
     "M.send(foo, \"bar\", _makeList.run(x, y), _makeMap.fromPairs(_makeList.run()))"],

    ["def [x, y] := [1, x]",
     "
     def [x_1, xR_2] := Ref.promise()
     def value_3 := def [x, y] := _makeList.run(1, x_1)
     xR_2.resolve(x)
     value_3"],

    ["def x",
     "
     def [x, x_Resolver] := Ref.promise()
     x_Resolver"],

    ["x :y",
     "y.coerce(x, throw)"],
#     "ValueGuard.coerce(y, throw).coerce(x, throw)"],

    ["def &x := y",
     "def via (_slotToBinding) &&x := y"],

    ["return",
     "__return.run()"],

    ["return 1",
     "__return.run(1)"],

    ["break",
     "__break.run()"],

    ["break 1",
     "__break.run(1)"],

    ["continue",
     "__continue.run()"],

    ["continue 1",
     "__continue.run(1)"],

    # Hi! This expansion is no longer as inefficient as it used to be due to a
    # special case. ~ C.
    ["x && y",
     "if (x) {
         if (y) {
             true
         } else {
             false
         }
     } else {
         false
     }"],

    ["(def x := 1) && (def y := 2)",
     "
     (def [ok_1, &&x, &&y] := if (def x := 1) {
         if (def y := 2) {
             _makeList.run(true, &&x, &&y)
         } else {
             _booleanFlow.failureList(2)
         }
     } else {
         _booleanFlow.failureList(2)
     }
     ok_1)"],

    ["x || y",
     "(if (x) {
         true
     } else if (y) {
         true
     } else {
         false
     })"],

    ["(def x := 1) || (def y := 2)",
     "
     (def [ok_1, &&x, &&y] := if (def x := 1) {
         def &&y := _booleanFlow.broken()
         _makeList.run(true, &&x, &&y)
     } else if (def y := 2) {
         def &&x := _booleanFlow.broken()
         _makeList.run(true, &&x, &&y)
     } else {
         _booleanFlow.failureList(2)
     }
     ok_1)"],

    ["x =~ y",
     "
     def sp_1 := x
     def [ok_2, &&y] := escape fail_3 {
         def y exit fail_3 := sp_1
         _makeList.run(true, &&y)
     } catch problem_4 {
         def via (_slotToBinding) &&broken_5 := Ref.broken(problem_4)
         _makeList.run(false, &&broken_5)
     }
     ok_2"],

    ["def x ? (e) := z",
     "def via (_suchThat) [x, via (_suchThat.run(e)) _] := z"],

    ["def x ? (f(x) =~ y) := z",
     "
     def via (_suchThat) [x, via (_suchThat.run((def sp_1 := f.run(x)
     def [ok_2, &&y] := escape fail_3 {
         def y exit fail_3 := sp_1
         _makeList.run(true, &&y)
     } catch problem_4 {
         def via (_slotToBinding) &&broken_5 := Ref.broken(problem_4)
         _makeList.run(false, &&broken_5)
     }
     ok_2))) _] := z"],

    [`def ["a" => b, "c" => d := (3)] := x`,
     `def via (_mapExtract.run("a")) [b, via (_mapExtract.withDefault("c", 3)) [d, _ :_mapEmpty]] := x`],

    ["def [(a) => b] | c := x",
     "def via (_mapExtract.run(a)) [b, c] := x"],

    ["def [=> b] := x",
     "def via (_mapExtract.run(\"b\")) [b, _ :_mapEmpty] := x"],

    ["def [=> &b] := x",
     "def via (_mapExtract.run(\"&b\")) [via (_slotToBinding) &&b, _ :_mapEmpty] := x"],

    [`["a" => b, "c" => d]`,
     `_makeMap.fromPairs(_makeList.run(_makeList.run("a", b), _makeList.run("c", d)))`],

    [`[=> a, => &b]`,
     `_makeMap.fromPairs(_makeList.run(_makeList.run("a", a), _makeList.run("&b", (&&b).get())))`],

    ["
     for x in y:
          z
     ",
     "
     var validFlag_1 := true
     try:
         _loop.run(y, object _ {
             \"For-loop body\"
             method run(_, x) {
                 _validateFor.run(validFlag_1)
                 z
                 null
             }

         })
     finally:
         validFlag_1 := false
     null"],
    ["[for x in (y) if (a) z]",
     "
     var validFlag_1 := true
     try:
         _accumulateList.run(y, object _ {
             \"For-loop body\"
             method run(_, x, skip_2) {
                 _validateFor.run(validFlag_1)
                 if (a) {
                     z
                 } else {
                     skip_2.run()
                 }
             }

         })
     finally:
         validFlag_1 := false"],

    ["[for x in (y) if (a) k => v]",
     "
     var validFlag_1 := true
     try:
         _accumulateMap.run(y, object _ {
             \"For-loop body\"
             method run(_, x, skip_2) {
                 _validateFor.run(validFlag_1)
                 if (a) {
                     _makeList.run(k, v)
                 } else {
                     skip_2.run()
                 }
             }

         })
     finally:
         validFlag_1 := false"],

    ["
     while (x):
         y
     ",

     "
     escape __break:
         _loop.run(_iterForever, object _ {
             method run(_, _) :Bool {
                 if (x) {
                     y
                     true
                 } else {
                     __break.run()
                 }
             }

         })"],
    ["
     object foo extends (baz.get()):
         pass
     ",
     "
     def foo := {
         def super := baz.get()
         object foo {
             match pair_1 {
                 M.callWithMessage(super, pair_1)
             }

         }
     }"],
    ["
     object foo:
         to baz():
             x
     ",
     "
     object foo:
         method baz():
             x
             null
     "],
    ["
     def foo():
         x
     ",
     "
     object foo:
         method run():
             x
             null
     "],
    ["
     switch (x):
         match [a, b]:
             c
         match x:
             y
     ",
     "
     {
         def specimen_1 := x
         escape ej_2 {
             def [a, b] exit ej_2 := specimen_1
             c
         } catch failure_3 {
             escape ej_4 {
                 def x exit ej_4 := specimen_1
                 y
             } catch failure_5 {
                 _switchFailed.run(specimen_1, failure_3, failure_5)
             }
         }
     }"],
    ["
     switch (x):
         match ==2:
             'a'
     ",
     "
     {
         def specimen_1 := x
         escape ej_2 {
             def via (_matchSame.run(2)) _ exit ej_2 := specimen_1
             'a'
         } catch failure_3 {
             _switchFailed.run(specimen_1, failure_3)
         }
     }"],
     ["
      interface foo:
          pass
      ",
      "
      def foo := {
          _makeProtocolDesc.run(null, meta.context().getFQNPrefix().add(\"foo_T\"), _makeList.run(), _makeList.run(), _makeList.run())
      }"],
     [`
      interface foo extends x, y implements a, b:
          "yay"
          to baz(c :Int):
              "blee"
          to boz(d) :Double
      `,
      `
      def foo := {
          _makeProtocolDesc.run("yay", meta.context().getFQNPrefix().add("foo_T"), _makeList.run(x, y), _makeList.run(a, b), _makeList.run({
              _makeMessageDesc.run("blee", "baz", _makeList.run(_makeParamDesc.run("c", Int)), Any)
          }, {
              _makeMessageDesc.run(null, "boz", _makeList.run(_makeParamDesc.run("d", Any)), Double)
          }))
      }`],
     ["
      try:
          x
      catch p:
          y
      catch q:
          z
      ",
      "
      try:
          try:
              x
          catch p:
              y
      catch q:
          z"],
     ["
      try:
          x
      catch p:
          y
      finally:
          z
      ",
      "
      try:
          try:
              x
          catch p:
              y
      finally:
          z"],
    ["
     when (x) ->
         y
     ",
     "
     Ref.whenResolved(x,
     object _ {
         \"when-catch 'done' function\"
         method run(resolution_1) {
             if (Ref.isBroken(resolution_1)) {
                 resolution_1
             } else {
                 y
             }
         }

     })
     "],
    ["
     when (x) ->
         y
     catch p:
         z
     ",
     "
     Ref.whenBroken(
     Ref.whenResolved(x,
     object _ {
         \"when-catch 'done' function\"
         method run(resolution_1) {
             if (Ref.isBroken(resolution_1)) {
                 resolution_1
             } else {
                 y
             }
         }

     }),
     object _ {
         \"when-catch 'catch' function\"
         method run(broken_2) {
             def problem_3 := Ref.optProblem(broken_2)
             escape fail_4 {
                 def p exit fail_4 := problem_3
                 z
             } catch _ {
                 problem_3
             }
         }

     })"],
     ["`hello $x world`",
      `simple__quasiParser.valueMaker(_makeList.run("hello ", simple__quasiParser.valueHole(0), " world")).substitute(_makeList.run(x))`],
     ["def foo`(@x)` := 1",
      `def via (_quasiMatcher.run(foo__quasiParser.matchMaker(_makeList.run("(", foo__quasiParser.patternHole(0), ")")), _makeList.run())) [x] := 1`],
     ["def foo`(@x:$y)` := 1",
      `def via (_quasiMatcher.run(foo__quasiParser.matchMaker(_makeList.run("(", foo__quasiParser.patternHole(0), ":", foo__quasiParser.valueHole(0), ")")), _makeList.run(y))) [x] := 1`],
    ["exports (foo); def foo := 1",
     `object _ as DeepFrozen {
          method run(package_1) :(Map.get(Str, DeepFrozen)) {
              def foo := 1
              _makeMap.fromPairs(_makeList.run(_makeList.run("foo", foo)))
          }
          method dependencies() :(List.get(Str)) {
              "The dependencies of this module."
              _makeList.run()
          }
      }`],
    [`import "blee" =~ p; exports (foo); def foo := 1`,
     `object _ as DeepFrozen {
          method run(package_1) :(Map.get(Str, DeepFrozen)) {
              def p := package_1."import"("blee")
              def foo := 1
              _makeMap.fromPairs(_makeList.run(_makeList.run("foo", foo)))
          }
          method dependencies() :(List.get(Str)) {
              "The dependencies of this module."
              _makeList.run("blee")
          }
      }`],
    [`import "blee" =~ [=> a] | b; exports (foo); def foo := 1`,
     `object _ as DeepFrozen {
          method run(package_1) :(Map.get(Str, DeepFrozen)) {
              def via (_mapExtract.run("a")) [a, b] := package_1."import"("blee")
              def foo := 1
              _makeMap.fromPairs(_makeList.run(_makeList.run("foo", foo)))
          }
          method dependencies() :(List.get(Str)) {
              "The dependencies of this module."
              _makeList.run("blee")
          }
      }`],
    [`import "blee" =~ [=> a]; exports (foo); def foo := 1`,
     `object _ as DeepFrozen {
          method run(package_1) :(Map.get(Str, DeepFrozen)) {
              def via (_mapExtract.run("a")) [a, _] := package_1."import"("blee")
              def foo := 1
              _makeMap.fromPairs(_makeList.run(_makeList.run("foo", foo)))
          }
          method dependencies() :(List.get(Str)) {
              "The dependencies of this module."
              _makeList.run("blee")
          }
      }`]
]

def trim(var s):
    if (s[0] == '\n'):
        s := s.slice(1, s.size())
    def lines := s.split("\n")
    var dent := 0
    for line in lines:
        for i => c in line:
            if (c != ' '):
                dent := i
                break
        break
    def trimmedLines := [].diverge()
    for line in lines:
        trimmedLines.push(line.slice(dent, line.size()))
    def out := "\n".join(trimmedLines) + "\n"
    return out

def expandit(code):
    def node := parseModule(makeMonteLexer(trim(code), "<test>"), astBuilder, throw)
    return expand(node, astBuilder, throw)

for item in fixedPointSpecimens:
    tests.push(fn assert {
        def node := parseModule(makeMonteLexer(trim(item), "<test>"),
                                astBuilder, throw)
        assert.equal(expand(node, astBuilder, throw).canonical(), node.canonical())
    })

for [specimen, result] in specimens:
    tests.push(fn assert {
        def specimenNode := parseModule(
            makeMonteLexer(trim(specimen), "<test>"),
            astBuilder, throw)
        def resultNode := parseModule(
            makeMonteLexer(trim(result), "<test>"),
            astBuilder, throw)
        assert.equal(expand(specimenNode, astBuilder, throw).canonical(), resultNode.canonical())
    })

unittest(tests.snapshot())
