import "lib/streams" =~ [=> flow]
exports (makeVampEndpoint)

def makeVampEndpoint(currentProcess, makeProcess, host :Bytes, port :Int) as DeepFrozen:
    "
    An endpoint which can make many connections to `host` at `port` with
    `tools/vamp` workers.

    The authority of `currentProcess` and `makeProcess` are both required;
    this endpoint uses information about the current process in order to
    determine which executable and standard library to use.
    "

    def exe :Bytes := currentProcess.getExecutable()
    def args :List[Bytes] := {
        def l := currentProcess.getArguments()
        traceln("current args", l)
        def i := l.indexOf(b`run`)
        traceln("run index", i)
        if (i == -1) {
            throw(`Confounded by non-standard Monte invocation $l`)
        } else {
            l.slice(0, i) + [b`run`, b`tools/vamp`, host,
                             _makeBytes.fromStr(M.toString(port))]
        }
    }
    # def env :Map[Bytes, Bytes] := currentProcess.getEnvironment()
    def env :Map[Bytes, Bytes] := [].asMap()

    return def startVamping.connectWorkers(count :Int):
        "Make `count` subprocesses and connect them all."

        return [for i in (0..!count) {
            def p := makeProcess(exe, args, env, "stderr" => true)
            flow(p<-stderr(), object logger {
                to run(data) { traceln(`stderr from vamp worker $i:`, data) }
                to complete() { traceln(`vamp worker $i exited cleanly`) }
                to abort(problem) {
                    traceln(`vamp worker $i had problem:`, problem)
                }
            })
            # XXX wait?
        }]
