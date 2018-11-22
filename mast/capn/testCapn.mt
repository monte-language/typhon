# Doesn't use 'unittest' because of dependency on `makeProcess`.
import "testRunner" =~ [=> makeRunner :DeepFrozen]
import "lib/capn" =~ capn :DeepFrozen
import "lib/enum" =~ enum :DeepFrozen
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "tools/capnpc" =~ ["main" => capnpc :DeepFrozen]
exports (main)

def [=> makeMessageReader :DeepFrozen] | _ := capn

def main(_argv, => currentProcess, => makeProcess, => makeFileResource, => stdio, => unsealException, => Timer) as DeepFrozen:
    def [ (b`CAPNPC`) => CAPNPC ] | _ := currentProcess.getEnvironment()
    def compile(schema, name):
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
            traceln(readMAST(result))
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
            def pt := writer.makePoint(3, 4)
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
            def pt := writer.makePoint(1, 2, enums["Color"]["yellow"])
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


    def stdout := stdio.stdout()
    def runner := makeRunner(stdout, unsealException, Timer)
    return when (def t := runner.runTests([
            ["testTrivial", testTrivial],
            ["testEnum", testEnum],
        ])) -> {
            def fails :Int := t.fails()
            stdout(b`${M.toString(t.total())} tests run, `)
            stdout(b`${M.toString(fails)} failures$\n`)
            for loc => errors in (t.errors()) {
                stdout(b`In $loc:$\n`)
                for error in (errors) { stdout(b`~ $error$\n`) }
            }
            fails.min(1)
        } catch problem {
            stdout(b`Test suite failed: ${M.toString(unsealException(problem))}$\n`)
            1
        }
