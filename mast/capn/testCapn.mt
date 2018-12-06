# Doesn't use 'unittest' because of dependency on `makeProcess`.
import "testRunner" =~ [=> makeRunner :DeepFrozen]
import "lib/capn" =~ capn :DeepFrozen
import "lib/enum" =~ enum :DeepFrozen
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "tools/capnpc" =~ ["main" => capnpc :DeepFrozen]
exports (main)

def [=> makeMessageReader :DeepFrozen] | _ := capn

def formatWords(bs) as DeepFrozen:
    return def words._printOn(out) {
    out.print("\n".join([for i in (0..!(bs.size() // 8)) M.toString(bs.slice(i*8, i*8 + 8))])) }

def main(_argv, => currentProcess, => makeProcess, => makeFileResource, => stdio, => unsealException, => Timer) as DeepFrozen:
    def [ (b`CAPNPC`) => CAPNPC ] | _ := currentProcess.getEnvironment()
    def compile(schema, name, => dump := false):
        def tmp := makeFileResource(`/tmp/test_$name.capnp`).setContents(
            UTF8.encode(schema, null))
        def schemaMsg := when (tmp) -> {
            def pr := makeProcess(
                CAPNPC,
                [b`capnpc`, b`-o-`, b`/tmp/test_$name.capnp`],
                [].asMap(),
                "stdout" => true,
            )
            pr.stdout()
        }
        def result
        object capnpcIO:
            to stdin():
                return schemaMsg
            to stdout():
                return object _:
                    to run(output):
                        bind result := output
                    to complete():
                        null

        when (schemaMsg) ->
            try:
                capnpc([], "stdio" => capnpcIO)
            catch err0:
                traceln.exception(err0)
        catch err:
            traceln.exception(err)
        def mod := when (result) -> {
            if (dump) { traceln(readMAST(result)) }
            def mast := normalize(readMAST(result), typhonAstBuilder)
            def schemaModule := typhonAstEval(
                mast,
                safeScope,
                "<testCapn>")
            schemaModule(def ldr."import"(name) { return ["lib/capn" => capn, "lib/enum" => enum][name] })
        }
        return mod

    def testTrivial(assert):
        def schema := "
            @0xe62e66ea90a396da;
            struct Point {
                x @0 :Int64;
                y @1 :Int64;
            }"
        return when (def m := compile(schema, "trivial")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makePoint("x" => 3, "y" => 4)
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 3, 0, 0, 0,
                 0, 0, 0, 0, 2, 0, 0, 0,
                 3, 0, 0, 0, 0, 0, 0, 0,
                 4, 0, 0, 0, 0, 0, 0, 0,
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Point(root)
            assert.equal(p.x(), 3)
            assert.equal(p.y(), 4)

    def testEnum(assert):
        def schema := "
            @0xbf5147cbbecf40c1;
            enum Color {
                red @0;
                green @1;
                blue @2;
                yellow @3;
            }
            struct Point {
                x @0 :Int64;
                y @1 :Int64;
                color @2 :Color;
            }"
        return when (def m := compile(schema, "enum")) ->
            def [=> enums, => reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makePoint("x" => 1, "y" => 2,
                                       "color" => enums["Color"]["yellow"])
            def bs := writer.dump(pt)
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Point(root)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 4, 0, 0, 0,
                 0, 0, 0, 0, 3, 0, 0, 0,
                 1, 0, 0, 0, 0, 0, 0, 0,
                 2, 0, 0, 0, 0, 0, 0, 0,
                 3, 0, 0, 0, 0, 0, 0, 0,
                ])
            assert.equal(p.x(), 1)
            assert.equal(p.y(), 2)
            assert.equal(p.color(), enums["Color"]["yellow"])

    def testOrder(assert):
        def schema := "
            @0xe62e66ea90a396da;
            struct Point {
                x @0 :Int8;
                y @1 :Int64;
                z @2 :Int8;
            }"
        return when (def m := compile(schema, "order")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makePoint("z" => 3, "x" => 1, "y" => 2)
            def bs := writer.dump(pt)
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Point(root)
            assert.equal(p.x(), 1)
            assert.equal(p.y(), 2)
            assert.equal(p.z(), 3)

    def testVoid(assert):
        def schema := "
            @0xe62e66ea90a396da;
            struct Point {
                x @0 :Int8;
                y @1 :Int64;
                z @2 :Void;
            }"
        return when (def m := compile(schema, "void")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makePoint("x" => 1, "y" => 2)
            def bs := writer.dump(pt)
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Point(root)
            assert.equal(p.x(), 1)
            assert.equal(p.y(), 2)
            assert.equal(p.z(), null)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 3, 0, 0, 0,
                 0, 0, 0, 0, 2, 0, 0, 0,
                 1, 0, 0, 0, 0, 0, 0, 0,
                 2, 0, 0, 0, 0, 0, 0, 0,
                ])

    def testText(assert):
        def schema := "
            @0xe62e66ea90a396da;
            struct Point {
                x @0 :Int64;
                y @1 :Text;
            }"
        return when (def m := compile(schema, "text")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makePoint("x" => 1, "y" => "hello capnp")
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                _makeList.fromIterable(
                    b`$\x00$\x00$\x00$\x00$\x05$\x00$\x00$\x00` +
                    b`$\x00$\x00$\x00$\x00$\x01$\x00$\x01$\x00` +
                    b`$\x01$\x00$\x00$\x00$\x00$\x00$\x00$\x00` +
                    b`$\x01$\x00$\x00$\x00$\x62$\x00$\x00$\x00` +
                    b`hello ca` +
                    b`pnp$\x00$\x00$\x00$\x00$\x00`))
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Point(root)
            assert.equal(p.x(), 1)
            assert.equal(p.y(), "hello capnp")

    def testData(assert):
        def schema := "
            @0xe62e66ea90a396da;
            struct Point {
                x @0 :Int64;
                y @1 :Data;
            }"
        return when (def m := compile(schema, "data")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makePoint("x" => 1, "y" => b`hello capnp`)
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                _makeList.fromIterable(
                    b`$\x00$\x00$\x00$\x00$\x05$\x00$\x00$\x00` +
                    b`$\x00$\x00$\x00$\x00$\x01$\x00$\x01$\x00` +
                    b`$\x01$\x00$\x00$\x00$\x00$\x00$\x00$\x00` +
                    b`$\x01$\x00$\x00$\x00$\x5a$\x00$\x00$\x00` +
                    b`hello ca` +
                    b`pnp$\x00$\x00$\x00$\x00$\x00`))
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Point(root)
            assert.equal(p.x(), 1)
            assert.equal(p.y(), b`hello capnp`)

    def testStruct(assert):
        def schema := "
            @0xbf5147cbbecf40c1;
            struct Point {
                x @0 :Int64;
                y @1 :Int64;
            }
            struct Foo {
                x @0 :Point;
            }"
        return when (def m := compile(schema, "struct")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makeFoo("x" => writer.makePoint("x" => 3, "y" => 4))
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 4, 0, 0, 0,
                 8, 0, 0, 0, 0, 0, 1, 0,
                 3, 0, 0, 0, 0, 0, 0, 0,
                 4, 0, 0, 0, 0, 0, 0, 0,
                 0xf4, 0xff, 0xff, 0xff, 2, 0, 0, 0,
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Foo(root).x()
            assert.equal(p.x(), 3)
            assert.equal(p.y(), 4)

    def testList(assert):
        def schema := "
            @0xbf5147cbbecf40c1;
            struct Foo {
                x @0 :List(Int8);
            }"
        return when (def m := compile(schema, "list")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makeFoo("x" => [1, 2, 3, 4])
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 3, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 1, 0,
                 1, 0, 0, 0, 0x22, 0, 0, 0,
                 1, 2, 3, 4, 0, 0, 0, 0,
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Foo(root)
            assert.equal(p.x(), [1, 2, 3, 4])

    def testListOfVoid(assert):
        def schema := "
            @0xbf5147cbbecf40c1;
            struct Foo {
                x @0 :List(Void);
            }"
        return when (def m := compile(schema, "list_void")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makeFoo("x" => [null, null, null, null])
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 2, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 1, 0,
                 1, 0, 0, 0, 0x20, 0, 0, 0,
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Foo(root)
            assert.equal(p.x(), [null, null, null, null])

    def testListOfText(assert):
        def schema := "
            @0xbf5147cbbecf40c1;
            struct Foo {
                x @0 :List(Text);
            }"
        return when (def m := compile(schema, "list_text")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makeFoo("x" => ["foo", "bar", "baz"])
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 8, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 1, 0,
                 1, 0, 0, 0, 0x1e, 0, 0, 0,
                 9, 0, 0, 0, 0x22, 0, 0, 0,
                 9, 0, 0, 0, 0x22, 0, 0, 0,
                 9, 0, 0, 0, 0x22, 0, 0, 0,
                 0x66, 0x6f, 0x6f, 0, 0, 0, 0, 0, # foo
                 0x62, 0x61, 0x72, 0, 0, 0, 0, 0, # bar
                 0x62, 0x61, 0x7a, 0, 0, 0, 0, 0, # baz
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Foo(root)
            assert.equal(p.x(), ["foo", "bar", "baz"])

    def testListOfData(assert):
        def schema := "
            @0xbf5147cbbecf40c1;
            struct Foo {
                x @0 :List(Data);
            }"
        return when (def m := compile(schema, "list_data")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makeFoo("x" => [b`foo`, b`bar`, b`baz`])
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 8, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 1, 0,
                 1, 0, 0, 0, 0x1e, 0, 0, 0,
                 9, 0, 0, 0, 0x1a, 0, 0, 0,
                 9, 0, 0, 0, 0x1a, 0, 0, 0,
                 9, 0, 0, 0, 0x1a, 0, 0, 0,
                 0x66, 0x6f, 0x6f, 0, 0, 0, 0, 0, # foo
                 0x62, 0x61, 0x72, 0, 0, 0, 0, 0, # bar
                 0x62, 0x61, 0x7a, 0, 0, 0, 0, 0, # baz
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Foo(root)
            assert.equal(p.x(), [b`foo`, b`bar`, b`baz`])

    def testListOfStructs(assert):
        def schema := "
            @0xbf5147cbbecf40c1;
            struct Polygon {
                struct Point {
                    x @0 :Int64;
                    y @1 :Int64;
                }
                points @0 :List(Point);
            }"
        return when (def m := compile(schema, "list_structs")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def poly := writer.makePolygon(
                "points" => [["x" => 1, "y" => 2], ["x" => 3, "y" => 4]])
            def bs := writer.dump(poly)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 7, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 1, 0,
                 1, 0, 0, 0, 0x27, 0, 0, 0, # list ptr
                 8, 0, 0, 0, 2, 0, 0, 0,    # list tag
                 1, 0, 0, 0, 0, 0, 0, 0,
                 2, 0, 0, 0, 0, 0, 0, 0,
                 3, 0, 0, 0, 0, 0, 0, 0,
                 4, 0, 0, 0, 0, 0, 0, 0,
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Polygon(root)
            assert.equal(p.points()[0].x(), 1)
            assert.equal(p.points()[0].y(), 2)
            assert.equal(p.points()[1].x(), 3)
            assert.equal(p.points()[1].y(), 4)

    def testGroup(assert):
        def schema := "
        @0xbf5147cbbecf40c1;
        struct Point {
            position :group {
                x @0 :Int64;
                y @1 :Int64;
            }
            color @2 :Text;
        }"
        return when (def m := compile(schema, "group")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makePoint("position" => ["x" => 3, "y" => 4], "color" => "red")
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 5, 0, 0, 0,
                 0, 0, 0, 0, 2, 0, 1, 0,
                 3, 0, 0, 0, 0, 0, 0, 0,
                 4, 0, 0, 0, 0, 0, 0, 0,
                 1, 0, 0, 0, 0x22, 0, 0, 0,
                 0x72, 0x65, 0x64, 0, 0, 0, 0, 0
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Point(root)
            assert.equal(p.position().x(), 3)
            assert.equal(p.position().y(), 4)

    def testNestedGroups(assert):
        def schema := "
        @0xbf5147cbbecf40c1;
        struct Shape {
            position :group {
                a :group {
                    x @0 :Int64;
                    y @1 :Int64;
                }
                b :group {
                    x @2 :Int64;
                    y @3 :Int64;
                }
            }
        }"
        return when (def m := compile(schema, "nestedGroup")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makeShape("position" => ["a" => ["x" => 1, "y" => 2], "b" => ["x" => 3, "y" => 4]])
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 5, 0, 0, 0,
                 0, 0, 0, 0, 4, 0, 0, 0,
                 1, 0, 0, 0, 0, 0, 0, 0,
                 2, 0, 0, 0, 0, 0, 0, 0,
                 3, 0, 0, 0, 0, 0, 0, 0,
                 4, 0, 0, 0, 0, 0, 0, 0
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Shape(root)
            assert.equal(p.position().a().x(), 1)
            assert.equal(p.position().a().y(), 2)
            assert.equal(p.position().b().x(), 3)
            assert.equal(p.position().b().y(), 4)

    def testTrivialUnion(assert):
        def schema := "
        @0xbf5147cbbecf40c1;
        struct Shape {
          area @0 :Int64;
          perimeter @1 :Int64;
          union {
            circle @2 :Int64;      # radius
            square @3 :Int64;      # width
            empty  @4 :Void;
            fooBar @5 :Void;
          }
        }"
        return when (def m := compile(schema, "trivialUnion")) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makeShape("area" => 1, "circle" => 2, "perimeter" => 3)
            def bs := writer.dump(pt)
            assert.equal(
                _makeList.fromIterable(bs),
                [0, 0, 0, 0,
                 5, 0, 0, 0,
                 0, 0, 0, 0, 4, 0, 0, 0,
                 1, 0, 0, 0, 0, 0, 0, 0,
                 3, 0, 0, 0, 0, 0, 0, 0,
                 2, 0, 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 0, 0
                ])
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Shape(root)
            assert.equal(p.area(), 1)
            assert.equal(p.perimeter(), 3)
            assert.equal(p._which(), 0)
            assert.equal(p.circle(), 2)
            def qt := writer.makeShape("area" => 1, "empty" => null, "perimeter" => 3)
            def q := reader.Shape(makeMessageReader(writer.dump(qt)).getRoot())
            assert.equal(q._which(), 2)
            assert.equal(q.empty(), null)
            assert.equal(q.perimeter(), 3)
            def err := assert.throws(fn {writer.makeShape("empty" => null, "circle" => 2)})
            assert.equal(unsealException(err, null)[0], `Can't provide both "circle" and "empty" fields of union`)

    def stdout := stdio.stdout()
    def print(via (UTF8.encode) msg) { stdout(msg) }
    def runner := makeRunner(stdout, unsealException, Timer)
    return when (def t := runner.runTests([
            ["testTrivial", testTrivial],
            ["testEnum", testEnum],
            ["testOrder", testOrder],
            ["testVoid", testVoid],
            ["testText", testText],
            ["testData", testData],
            ["testStruct", testStruct],
            ["testList", testList],
            ["testListOfVoid", testListOfVoid],
            ["testListOfText", testListOfText],
            ["testListOfData", testListOfData],
            ["testListOfStructs", testListOfStructs],
            ["testGroup", testGroup],
            ["testNestedGroups", testNestedGroups],
            ["testTrivialUnion", testTrivialUnion],
        ])) -> {
            def fails :Int := t.fails()
            print(`${M.toString(t.total())} tests run, `)
            print(`${M.toString(fails)} failures$\n`)
            for loc => errors in (t.errors()) {
                print(`In $loc:$\n`)
                for error in (errors) { print(`~ $error$\n`) }
            }
            fails.min(1)
        } catch problem {
            print(`Test suite failed: ${M.toString(unsealException(problem, null))}$\n`)
            1
        }
