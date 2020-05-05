import "lib/mim/anf" =~ [=> makeNormal]
import "lib/mim/full" =~ [=> expand]
exports (main)

def outers :Map[Str, Bytes] := [
    "_makeList" => b`makeList`,
]

def compileProgramOnto(expr, lines) :Bytes as DeepFrozen:
    object compiler:
        to LiteralExpr(x, _span):
            return switch (x) {
                match i :Int { b`new(Int, $$I(${M.toString(i)}))` }
            }

        to NounExpr(name, _span):
            return if (outers.contains(name)) {
                b`copy($$(Function, ${outers[name]}))`
            } else { b`$name` }

        to Atom(atom, _span):
            return atom

        to LetExpr(pattern, expr, body, _span):
            lines.push(b`var $pattern = $expr;`)
            return body

        to MethodCallExpr(receiver, verb :Str, args, _namedArgs, _span):
            def newVerb := b`new(String, $$S(${M.toQuote(verb)}))`
            def packedArgs := b`new(Tuple, ${b`,`.join(args)})`
            # XXX namedArgs
            def emptyMap := b`new(Table, Ref, Ref)`
            return b`call($receiver, $newVerb, $packedArgs, $emptyMap)`

        to FinalPattern(noun, _span):
            return b`$noun`

        match [verb, args, _]:
            throw(`Next to do: $verb/${args.size()}`)
    return expr(compiler)

def buildEntrypoint(lines :List[Bytes], module :Bytes) :Bytes as DeepFrozen:
    def preamble := b`$\n`.join(lines)
    def externFuns := b`$\n`.join([for v in (outers) b`var $v(var);`])
    return b`
    #include "Cello.h"

    extern var ConstList;

    $externFuns

    var monteEntrypoint() {
        print("\nIn entrypoint\n");

        $preamble

        var rv = $module;
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

def expr :DeepFrozen := m`[6, 7].size()`

def main(_argv, => stdio) as DeepFrozen:
    def lines := [].diverge(Bytes)
    def normalized := makeNormal().alpha(expand(expr))
    traceln(normalized)
    def rv := compileProgramOnto(normalized, lines)
    def program := buildEntrypoint(lines.snapshot(), rv)
    def stdout := stdio.stdout()
    return when (stdout<-(program)) ->
        when (stdout<-complete()) -> { 0 }
