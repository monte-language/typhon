# Doesn't use 'unittest' because of dependency on `makeProcess`.
import "testRunner" =~ [=> makeRunner :DeepFrozen]
import "lib/capn" =~ capn :DeepFrozen
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "tools/capnpc" =~ ["main" => capnpc :DeepFrozen]
exports (main)

def [=> makeMessageReader :DeepFrozen] | _ := capn

def main(_argv, => currentProcess, => makeProcess, => makeFileResource, => stdio, => unsealException, => Timer) as DeepFrozen:
    def [ (b`CAPNPC`) => CAPNPC ] | _ := currentProcess.getEnvironment()
    def compile(schema):
        def tmp := makeFileResource("/tmp/test.capnp").setContents(
            UTF8.encode(schema, null))
        def schemaMsg := when (tmp) -> {
            def pr := makeProcess(
                CAPNPC,
                [b`capnpc`, b`-o-`, b`/tmp/test.capnp`],
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
            # traceln(readMAST(result))
            def mast := normalize(readMAST(result), typhonAstBuilder)
            def schemaModule := typhonAstEval(
                mast,
                safeScope,
                "<testCapn>")
            schemaModule(def ldr."import"(name) { return ["lib/capn" => capn][name] })
        }
        return mod

    def testTrivial(assert):
        def schema := "
            @0xe62e66ea90a396da;
            struct Point {
                x @0 :Int64;
                y @1 :Int64;
            }"
        return when (def m := compile(schema)) ->
            def [=> reader, => makeWriter] | _ := m
            def writer := makeWriter()
            def pt := writer.makePoint(3, 4)
            def bs := writer.dump(pt)
            def root := makeMessageReader(bs).getRoot()
            def p := reader.Point(root)
            assert.equal(p.x(), 3)
            assert.equal(p.y(), 4)
    def runner := makeRunner(stdio.stdout(), unsealException, Timer)
    return when (def t := runner.runTests([["testTrivial", testTrivial]])) -> {
            traceln(`$\n$\ntests run: ${t.total()}`)
            0
    }
