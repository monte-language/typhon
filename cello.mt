import "lib/mim/anf" =~ [=> makeNormal]
import "lib/mim/full" =~ [=> expand]
exports (main)

def outers :Map[Str, Bytes] := [
    "_makeList" => b`makeList`,
]

def compileProgramOnto(expr, _lines) :Bytes as DeepFrozen:
    object compiler:
        to LiteralExpr(x, _span):
            return switch (x) {
                match i :Int { b`new(Int, $$I(${M.toString(i)}))` }
            }

        to NounExpr(name, _span):
            return b`copy($$(Function, ${outers[name]}))`

        to Atom(atom, _span):
            return atom

        to MethodCallExpr(receiver, verb :Str, args, _namedArgs, _span):
            def newVerb := b`new(String, $$S(${M.toQuote(verb)}))`
            def packedArgs := b`new(Tuple, ${b`,`.join(args)})`
            # XXX namedArgs
            def emptyMap := b`new(Table, Monte, Monte)`
            return b`call($receiver, $newVerb, $packedArgs, $emptyMap)`

        match [verb, args, _]:
            throw(`Next to do: $verb/${args.size()}`)
    return expr(compiler)

def buildEntrypoint(module :Bytes) :Bytes as DeepFrozen:
    def externs := b`$\n`.join([for v in (outers) b`var $v(var);`])
    return b`
    #include "Cello.h"

    extern var Monte;

    $externs

    var monteEntrypoint() {
        print("\nIn entrypoint\n");
        var rv = Terminal;
        rv = $module;
        return rv;
    }

    int main(int argc, char** argv) {
        print("\nTop of main\n");
        exception_signals();
        print("\nStarting running\n");
        var rv = monteEntrypoint();
        print("\nFinished running\n");
        show(rv);
        print("\nAbout to exit\n");
        return 0;
    }
    `

def expr :DeepFrozen := m`[42]`

def main(_argv, => stdio) as DeepFrozen:
    def lines := [].diverge(Bytes)
    def normalized := makeNormal().alpha(expand(expr))
    def rv := compileProgramOnto(normalized, lines)
    # def program := buildEntrypoint(b`$\n`.join(lines))
    def program := buildEntrypoint(rv)
    def stdout := stdio.stdout()
    return when (stdout<-(program)) ->
        when (stdout<-complete()) -> { 0 }
