import "lib/mim/anf" =~ [=> makeNormal]
import "lib/mim/expand" =~ [=> expand]
import "lib/mim/syntax/cello" =~ ["ASTBuilder" => celloBuilder]
exports (main)

def outers :Map[Str, Bytes] := [
    "_makeList" => b`makeList`,
    "true" => b`trueObj`,
    "false" => b`falseObj`,
    "null" => b`nullObj`,
    "Int" => b`guardInt`,
    "Any" => b`guardAny`,
]

# We compile simple expressions to C expressions, and complex expressions to C
# statements; each expression is returned, but statements are written out line
# by line onto `lines`. Patterns write C statements and return information
# about which local names were written.

object cello as DeepFrozen:
    to new(type :Str, params):
        return celloBuilder.Call("new", [celloBuilder.Name(type)] + params)

def compileProgramOnto(expr, lines) :Bytes as DeepFrozen:
    var locals := [].asMap()
    object compiler:
        to LiteralExpr(x, _span):
            return switch (x) {
                match i :Int {
                    cello.new("Int", [
                        celloBuilder.Call("$I", [celloBuilder.Int(i)]),
                    ])
                }
            }

        to NounExpr(name, _span):
            return if (outers.contains(name)) {
                celloBuilder.Call("copy", [
                    celloBuilder.Call("$", [
                        celloBuilder.Name("Function"),
                        celloBuilder.Name(outers[name]),
                    ]),
                ])
            } else { celloBuilder.Name(name) }

        to Atom(atom, _span):
            return atom

        to LetExpr(pattern, expr, body, _span):
            def ej := celloBuilder.Call("copy", [
                celloBuilder.Call("$", [
                    celloBuilder.Name("Function"),
                    celloBuilder.Name("nullObj"),
                ]),
            ])
            locals |= pattern(expr, ej)
            return body

        to MethodCallExpr(receiver, verb :Str, args, _namedArgs, _span):
            def newVerb := cello.new("String", [
                celloBuilder.Call("$S", [celloBuilder.Str(M.toQuote(verb))]),
            ])
            def packedArgs := cello.new("Tuple", args)
            # XXX namedArgs
            def emptyMap := cello.new("Table", [
                celloBuilder.Name("Ref"),
                celloBuilder.Name("Ref"),
            ])
            return celloBuilder.Call("call", [
                receiver, newVerb, packedArgs, emptyMap,
            ])

        to IfExpr(test, cons, alt, _span):
            return celloBuilder.Ternary(celloBuilder.Call("isTrue", [test]),
                                        cons, alt)

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

object asUglyC as DeepFrozen:
    to Procedure(rtype, name :Str, params, body):
        def ps := ",".join(params)
        def b := "\n".join(body)
        return `$rtype $name($ps) { $b }`

    to Statement(expr):
        return expr + ";"

    to Declare(lhs, rhs):
        return `$lhs = $rhs;`

    to Ret(expr):
        return `return $expr;`

    to Int(i):
        return M.toString(i)

    to Str(s):
        return M.toQuote(s)

    to Name(n):
        return n

    to Call(name, args):
        def a := ",".join(args)
        return `$name($a)`

    to Ternary(test, cons, alt):
        return `($test) ? ($cons) : ($alt)`

    to TypedName(type, name):
        return type + " " + name

def buildEntrypoint(lines :List[Bytes], module :Bytes) :Bytes as DeepFrozen:
    def preamble := b`$\n`.join(lines)
    def externFuns := b`$\n`.join([for v in (outers) b`var $v(var);`])
    return b`
    #include "Cello.h"

    extern var FinalSlot;
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
