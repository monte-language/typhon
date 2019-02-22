import "lib/asdl" =~ [=> asdlParser]
import "lib/codec/utf8" =~ [=> UTF8]
exports (qbe, main)

# https://c9x.me/compile/

# http://scheme2006.cs.uchicago.edu/11-ghuloum.pdf

def qbe :DeepFrozen := asdlParser(mpatt`qbe`, `
    ty = W | L | S | D | Agg(str name)
    func = Func(ty ty, str name, arg* params, block* blocks)
    block = Block(str label, inst* insts, jump end)
    jump = Jump(str label) | NonZero(str val, str nonzero, str zero)
         | Ret(str? val)
    inst = Bin(ty ty, str op, str retval, str left, str right)
         | Store(ty ty, str val, str addr)
         | Load(ty ty, str retval, str addr)
         | Alloc(int align, int size, str retval)
         | Copy(ty ty, str dest, str src)
         | Call(str val, ty ty, str retval, arg* args)
    arg = Arg(ty ty, str name)
`, null)

object stringify as DeepFrozen:
    to L():
        return "l"

    to W():
        return "w"

    to Agg(name):
        return ":" + name

    to Func(ty, name, params, blocks):
        return `function $ty $$$name(${",".join(params)}) {
        ${"\n".join(blocks)}
        }
        `

    to Block(label, insts, end):
        return `@@$label
        ${"\n".join(insts)}
        $end
        `

    to Jump(label):
        return "jmp " + label

    to NonZero(val, nonzero, zero):
        return `jnz $val, $nonzero, $zero`

    to Ret(val):
        return if (val == null) { "ret" } else { "ret " + val }

    to Bin(ty, op, retval, left, right):
        return `$retval =$ty $op $left, $right`

    to Store(ty, val, addr):
        return `store$ty $val, $addr`

    to Load(ty, retval, addr):
        return `$retval =$ty load$ty $addr`

    to Alloc(align, size, retval):
        return `$retval =l alloc$align $size`

    to Copy(ty, dest, src):
        return `$dest =$ty copy $src`

    to Call(val, ty, retval, args):
        return `$retval =$ty call $val(${",".join(args)})`

    to Arg(ty, name):
        return ty + " " + name

def doOffset(offset :Int) :Str as DeepFrozen:
    return M.toString(offset * 8)

def makeCompiler() as DeepFrozen:
    def L := qbe.L()

    def pieces := [].diverge()

    var counter := 0
    def nameMaker(ty) :Str:
        counter += 1
        return `_monte_${ty}_$counter`

    def dataCache := [].asMap().diverge()
    def fetchData(k, action):
        return dataCache.fetch(k, fn { dataCache[k] := action })

    return object compiler:
        to finish():
            return UTF8.encode("\n".join(pieces), null)

        to temp():
            return "%" + nameMaker("temp")

        to label():
            return "@" + nameMaker("label")

        to load(struct, offset :Int, target):
            def temp := compiler.temp()
            return [
                qbe.Bin(L, "add", temp, struct, doOffset(offset)),
                qbe.Load(L, target, temp),
            ]

        to store(struct, offset :Int, value):
            def temp := compiler.temp()
            return [
                qbe.Bin(L, "add", temp, struct, doOffset(offset)),
                qbe.Store(L, value, temp),
            ]

        to allocList(elements :List):
            def list := compiler.temp()
            def blocks := [qbe.Alloc(4, 3 * 8, list)].diverge()
            def allocTemp := compiler.temp()
            for i => elt in (elements.reverse()) {
                blocks.extend([
                    qbe.Alloc(4, 3 * 8, allocTemp),
                ] + (
                    compiler.store(allocTemp, 0, elt) +
                    compiler.store(allocTemp, 1, list) +
                    compiler.store(allocTemp, 2, M.toString(i))
                ) + [
                    qbe.Copy(L, list, allocTemp),
                ])
            }
            return [list, blocks]

        to allocMessage(verb, args, namedArgs):
            def message := compiler.temp()
            def stores := (
                compiler.store(message, 0, verb) +
                compiler.store(message, 1, args) +
                compiler.store(message, 2, namedArgs)
            )
            return [message, [qbe.Alloc(4, 3 * 8, message)] + stores]

        to constant(value):
            return fetchData(["constant", value], fn {
                def name := nameMaker("const")
                switch (value) {
                    match s :Str {
                        pieces.push(`
                            data $$$name = { b${M.toQuote(s)}, b 0 }
                        `)
                    }
                }
            })

        to prebuilt(value):
            return fetchData(["prebuilt", value], fn {
                def name := nameMaker("pbo")
                switch (value) {
                    match i :Int {
                        pieces.push(`
                            data $$$name = { l $$Int, b${M.toQuote(i)} }
                        `)
                    }
                }
            })

        to function(qbeExpr):
            def piece := qbeExpr(stringify)
            pieces.push(piece)

        to functionBuilder(ty, name, params):
            var label := compiler.label()
            var rv := compiler.temp()
            def blocks := [qbe.Block(label, [], qbe.Ret(rv))].diverge()
            return object builder:
                to finish():
                    def firstLabel := compiler.label()
                    def firstBlock := qbe.Block(firstLabel, [],
                                                qbe.Jump(label))
                    def func := qbe.Func(ty, name, params,
                                         [firstBlock] + blocks)
                    compiler.function(func)

                to expr(expr):
                    def [pl, pb] := compiler.compile(expr, rv, label)
                    label := pl
                    blocks.extend(pb)


        to compile(expr :DeepFrozen, rv, nextLabel :Str):
            return switch (expr.getNodeName()) {
                match =="LiteralExpr" {
                    def pbo := compiler.prebuilt(expr.getValue())
                    def label := compiler.label()
                    [label, qbe.Block(label, [qbe.Copy(qbe.L(), rv, pbo)], qbe.Jump(nextLabel))]
                }
                match =="MethodCallExpr" {
                    var blocks := []
                    def targetTemp := compiler.temp()
                    def verb := compiler.constant(expr.getVerb())
                    var nextArgLabel := compiler.label()
                    def rargTemps := [].diverge()
                    def rargs := [for arg in (expr.getArgs().reverse()) {
                        def argTemp := compiler.temp()
                        def [l, bs] := compiler.compile(arg, argTemp, nextArgLabel)
                        blocks += bs
                        nextArgLabel := l
                        rargTemps.push(argTemp)
                    }]
                    var label := compiler.label()
                    def insts := [].diverge()
                    # We can stack-allocate messages and argument lists
                    # because of the no-stale-stack-frames rule.
                    def [argsTemp, lbs] := compiler.allocList(rargTemps.reverse())
                    insts.extend(lbs)
                    def [message, mbs] := compiler.allocMessage(verb, argsTemp, "0")
                    insts.extend(mbs)
                    def script := compiler.temp()
                    def closure := compiler.temp()
                    def receiver := compiler.temp()
                    def callBlock := qbe.Block(label, insts +
                        compiler.load(receiver, 0, script) +
                        compiler.load(receiver, 1, closure) + [
                        qbe.Call(script, L, rv,
                            [qbe.Arg(L, closure), qbe.Arg(L, message)]),
                    ], qbe.Jump(nextLabel))
                    # Get the target.
                    def target := compiler.temp()
                    def [receiverLabel, receiverBlocks] := compiler.compile(expr.getReceiver(),
                                                   target, label)
                }
            }

def makePrelude(c) as DeepFrozen:
    def L := qbe.L()
    def W := qbe.W()

    c.function(qbe.Func(qbe.Agg("object"), "makeObject",
                        [qbe.Arg(L, "%tag"), qbe.Arg(L, "%data")], [
        qbe.Block("start", [
            qbe.Call("$calloc", L, "%p", [qbe.Arg(W, "2"), qbe.Arg(W, "8")]),
            qbe.Store(L, "%tag", "%p"),
            qbe.Bin(L, "add", "%q", "%p", "8"),
            qbe.Store(L, "%data", "%q"),
        ], qbe.Ret("%p"))
    ]))

    def list := qbe.Agg("list")
    c.function(qbe.Func(list, "makeCons",
                        [qbe.Arg(L, "head"), qbe.Arg(list, "rest")], [
        qbe.Block("start", [
            qbe.Call("$calloc", L, "%p", [qbe.Arg(W, "3"), qbe.Arg(W, "8")]),
        ] + c.store("%p", 0, "%head"), qbe.NonZero("%rest", "cons", "empty")),
        qbe.Block("cons", c.store("%p", 1, "%rest") + c.load("%rest", 2, "%size") + [
            qbe.Bin(L, "add", "%size", "%size", "1"),
        ] + c.store("%p", 2, "%size"), qbe.Ret("%p")),
        qbe.Block("empty", c.store("%p", 2, "1"), qbe.Ret("%p")),
    ]))

    c.function(qbe.Func(L, "listSize", [qbe.Arg(list, "list")], [
        qbe.Block("start", [], qbe.NonZero("%list", "cons", "empty")),
        qbe.Block("cons", c.load("%list", 2, "%size"), qbe.Ret("%size")),
        qbe.Block("empty", [], qbe.Ret("0")),
    ]))

    def go(script):
        def rv := [].diverge()

        # NB: One extra label for the end.
        def scriptParts := [for [verb, arity] => body in (script) [verb, arity, body]]
        def verbLabels := [for _ in (0..script.size()) c.label()]

        def treeStart := verbLabels[0]
        def treeEnd := verbLabels.last()

        for i => [verb, arity, body] in (scriptParts):
            def verbLabel := verbLabels[i]
            def nextVerbLabel := verbLabels[i + 1]
            def arityLabel := c.label()
            def doLabel := c.label()
            def isVerb := c.temp()
            def cmpArity := c.temp()
            def const := c.constant(verb)
            def len := M.toString(verb.size() + 1)
            rv.extend([
                qbe.Block(verbLabel, [
                    qbe.Call("$memcmp", W, isVerb,
                             [qbe.Arg(L, "%verb"), qbe.Arg(L, const),
                              qbe.Arg(W, len)]),
                ], qbe.NonZero(isVerb, nextVerbLabel, arityLabel)),
                qbe.Block(arityLabel, [
                    qbe.Bin(W, "ceql", cmpArity, "%arity", M.toString(arity)),
                ], qbe.NonZero(cmpArity, nextVerbLabel, doLabel)),
                qbe.Block(doLabel, body, qbe.Ret("%rv")),
            ])
        def start := qbe.Block("start", [
            qbe.Call("$listSize", L, "%arity", [qbe.Arg(list, "%args")]),
        ], qbe.Jump(treeStart))
        def end := qbe.Block(treeEnd, [
            # We are actually out of checks. So it is now time for failure.
            qbe.Call("$puts", W, "%_r", [qbe.Arg(L, c.constant("welp\n"))]),
        ], qbe.Ret("$theFailure"))
        return [start] + rv + [end]

    def getArgs(argTypes):
        def pieces := [].diverge()
        for arg => ty in (argTypes):
            def temp := "%_monte_arg_temp"
            def unwrap := switch (ty) {
                match ==Any { [] }
                match ==Int { c.load(temp, 1, temp) }
            }
            pieces.extend(c.load("%args", 0, temp) + unwrap + [
                qbe.Copy(L, arg, temp)
            ])
        return c.load("%args", 1, "%args").join(pieces)

    # XXX needs automatic bigint promotion
    def message := qbe.Agg("message")
    c.function(qbe.Func(qbe.Agg("object"), "Int",
                        [qbe.Arg(L, "%i"), qbe.Arg(message, "msg")], 
        go([
            ["add", 1] => getArgs(["%j" => Int]) + [
                qbe.Bin(L, "add", "%i", "%i", "%j"),
                qbe.Call("$makeObject", qbe.Agg("object"), "%rv",
                         [qbe.Arg(L, "$Int"), qbe.Arg(L, "%i")]),
            ],
            ["next", 0] => [
                qbe.Bin(L, "add", "%i", "%i", "1"),
                qbe.Call("$makeObject", qbe.Agg("object"), "%rv",
                         [qbe.Arg(L, "$Int"), qbe.Arg(L, "%i")]),
            ],
            ["previous", 0] => [
                qbe.Bin(L, "sub", "%i", "%i", "1"),
                qbe.Call("$makeObject", qbe.Agg("object"), "%rv",
                         [qbe.Arg(L, "$Int"), qbe.Arg(L, "%i")]),
            ],
        ])
    ))

def makeProgram(expr :DeepFrozen) :Bytes as DeepFrozen:
    def c := makeCompiler()
    makePrelude(c)
    def name := c.compile(expr)
    return b`
    # { l %script, l %data }
    type :object = { l, l }

    # { l %head, l %rest, l %size }
    type :list = { l, l, l }

    # { l %verb, l %args, l %namedArgs }
    type :message = { l, l, l }
    data $$theFailure = { l 0, l 0 }
    ` + c.finish() + b`
    data $$hello = { b"Hello from compiled native Monte!", b 0 }
    data $$landing = { b"Stuck the landing!", b 0 }
    data $$failed = { b"Failed to get an int", b 0 }
    export function w $$main() {
    @@start
        %r =w call $$puts(l $$hello)
        %obj =:object call $$$name(l 0)
        %r =w call $$puts(l $$landing)
        %tag =l loadl %obj
        %isInt =w ceql %tag, $$Int
        jnz %isInt, @@success, @@fail
    @@success
        %data =l add %obj, 8
        %rv =l loadl %data
        ret %rv
    @@fail
        %r =w call $$puts(l $$failed)
        ret -1
    }
    `

def main(_argv, => stdio) as DeepFrozen:
    def stdout := stdio.stdout()
    def expr := m`20.add(20).next().next()`
    def program := makeProgram(expr)
    return when (stdout<-(program)) ->
        when (stdout<-complete()) -> { 0 }
