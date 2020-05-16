import "lib/mim/anf" =~ [=> makeNormal]
import "lib/mim/full" =~ [=> expand]
exports (main)

def outers :Map[Str, Bytes] := [
    "_makeList" => b`makeList`,
    "true" => b`trueObj`,
    "false" => b`falseObj`,
    "null" => b`nullObj`,
    "Int" => b`guardInt`,
]

def compileProgramOnto(expr, lines) :Bytes as DeepFrozen:
    var locals := [].asMap()
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
            locals |= pattern(expr, b`copy($$(Function, nullObj))`)
            return body

        to MethodCallExpr(receiver, verb :Str, args, _namedArgs, _span):
            def newVerb := b`new(String, $$S(${M.toQuote(verb)}))`
            def packedArgs := b`new(Tuple, ${b`,`.join(args)})`
            # XXX namedArgs
            def emptyMap := b`new(Table, Ref, Ref)`
            return b`call($receiver, $newVerb, $packedArgs, $emptyMap)`

        to IfExpr(test, cons, alt, _span):
            return b`isTrue($test) ? ($cons) : ($alt)`

        to FinalPattern(noun, guard, _span):
            return fn expr, ej {
                if (guard == null) {
                    lines.push(b`var $noun = $expr;`)
                } else {
                    lines.push(b`var $noun = call($guard,
                        new(String, $$S("coerce")),
                        new(Tuple, $expr, $ej),
                        new(Table, Ref, Ref));`)
                }
                [noun => null]
            }

        match [verb, args, _]:
            throw(`Next to do: $verb/${args.size()}`)
    return expr(compiler)

def buildEntrypoint(lines :List[Bytes], module :Bytes) :Bytes as DeepFrozen:
    def preamble := b`$\n`.join(lines)
    def externFuns := b`$\n`.join([for v in (outers) b`var $v(var);`])
    return b`
    #include "Cello.h"

    extern var ConstList;

    bool isTrue(var);

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

def expr :DeepFrozen := m`{
    def x :Int := 6
    def y := 5
    if (true) { x } else { y }
}`

def main(_argv, => stdio) as DeepFrozen:
    def lines := [].diverge(Bytes)
    def normalized := makeNormal().alpha(expand(expr))
    traceln(normalized)
    def rv := compileProgramOnto(normalized, lines)
    def program := buildEntrypoint(lines.reverse(), rv)
    def stdout := stdio.stdout()
    return when (stdout<-(program)) ->
        when (stdout<-complete()) -> { 0 }
