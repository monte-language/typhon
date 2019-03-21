import "lib/mim/pipeline" =~ [=> go]
exports (makeCompiler, makeProgram, main)

# https://c9x.me/compile/

# http://scheme2006.cs.uchicago.edu/11-ghuloum.pdf

def makeCompiler() as DeepFrozen:
    def pieces := [].diverge()
    def funcs := [].asMap().diverge()

    var counter := 0
    def nameMaker(ty) :Bytes:
        counter += 1
        return b`_monte_${ty}_${M.toString(counter)}`

    def constCache := [].asMap().diverge()
    def pboCache := [].asMap().diverge()

    return object compiler:
        to finish():
            return b`$\n`.join(pieces)

        to temp():
            return b`%` + nameMaker(b`temp`)

        to constant(value):
            return if (value =~ i :Int) { b`${M.toString(i)}` } else {
                constCache.fetch(value, fn {
                    def name := b`$$` + nameMaker("const")
                    switch (value) {
                        match i :Int {
                            pieces.push(b`
                                data $name = ${M.toString(i)}
                            `)
                        }
                        match s :Str {
                            pieces.push(b`
                                data $name = { b${M.toQuote(s)}, b 0 }
                            `)
                        }
                    }
                    constCache[value] := name
                })
            }

        to prebuild(script :Bytes, value :DeepFrozen):
            return pboCache.fetch([script, value], fn {
                def name := b`$$` + nameMaker("pbo")
                pieces.push(b`
                    data $name = { l $$$script, l ${compiler.constant(value)} }
                `)
                pboCache[[script, value]] := name
            })

        to function(name :Bytes, ret :Str, args :Map[Str, Str], body :Bytes):
            if (funcs.contains(name)):
                throw(`Name $name was declared twice`)
            def params := b`,`.join([for n => ty in (args) b`$ty %$n`])
            funcs[name] := [ret, [for ty => _ in (args) ty]]
            pieces.push(b`
            function $ret $$$name($params) {
            @@_entrance
                jmp @@start
            @@fail
                ret $$theFailure
            @@start
                $body
            }
            `)

def makePrelude(c) as DeepFrozen:
    c.function(b`makeObject`, ":object", ["tag" => "l", "data" => "l"], b`
        %p =l call $$calloc(w 2, w 8)
        storel %tag, %p
        %q =l add %p, 8
        storel %data, %q
        ret %p
    `)

    def doOffset(offset):
        return M.toString(offset * 8)

    def load(struct, offset, target, => temp := b`%_load_temp_p`):
        return b`
            $temp =l add $struct, ${doOffset(offset)}
            $target =l loadl $temp
        `

    def store(struct, offset, value, => temp := b`%_store_temp_p`):
        return b`
            $temp =l add $struct, ${doOffset(offset)}
            storel $value, $temp
        `

    c.function(b`makeCons`, ":list", ["head" => "l", "rest" => ":list"], b`
        %p =l call $$calloc(w 3, w 8)
        ${store(b`%p`, 0, b`%head`)}
        jnz %rest, @@cons, @@empty
    @@cons
        ${store(b`%p`, 1, b`%rest`)}
        ${load(b`%rest`, 2, b`%size`)}
        %size =l add %size, 1
        ${store(b`%p`, 2, b`%size`)}
        ret %p
    @@empty
        ${store(b`%p`, 2, b`1`)}
        ret %p
    `)

    c.function(b`listSize`, "l", ["list" => ":list"], b`
        jnz %list, @@cons, @@empty
    @@cons
        ${load(b`%list`, 2, b`%size`)}
        ret %size
    @@empty
        ret 0
    `)

    def go(script):
        # Inelegant hack: We can't get a standard loop counter here, so we do
        # it by hand and deliberately make it cheap to compute the following
        # counter value (+1) in order to avoid running the loop twice. ~ C.
        var counter :Int := 0
        def tree := b`$\n`.join([for [verb :Str, arity] => body in (script) {
            def marker := M.toString(counter)
            def isVerb := b`%isItVerb$marker`
            def cmpArity := b`%cmpArity$marker`
            def const := c.constant(verb)
            def len := M.toString(verb.size() + 1)
            # So inelegant.
            counter += 1
            b`
            @@checkVerbFor$marker
                %_r =w call $$puts(l ${c.constant(`checking for verb $verb$\n`)})
                $isVerb =w call $$memcmp(l %verb, l $const, w $len)
                jnz $isVerb, @@checkVerbFor${M.toString(counter)}, @@checkArityFor$marker
            @@checkArityFor$marker
                %_r =w call $$puts(l ${c.constant(`checking for arity $arity$\n`)})
                $cmpArity =w ceql %arity, ${M.toString(arity)}
                jnz $cmpArity, @@checkVerbFor${M.toString(counter)}, @@do$marker
            @@do$marker
                %_r =w call $$puts(l ${c.constant(`entering method $verb/$arity$\n`)})
            ` + body
        }])
        return b`
            %arity =l call $$listSize(:list %args)
        ` + tree + b`
        @@checkVerbFor${M.toString(counter)}
            # We are actually out of checks. So it is now time for failure.
            %_r =w call $$puts(l ${c.constant("welp\n")})
            ret $$theFailure
        `

    def getArgs(argTypes):
        def pieces := [].diverge()
        for arg => ty in (argTypes):
            def temp := b`%_monte_arg_temp`
            def unwrap := switch (ty) {
                match ==Any { b`` }
                match ==Int { load(temp, 1, temp) }
            }
            pieces.push(b`
                ${load(b`%args`, 0, temp)}
                $unwrap
                $arg =l copy $temp
            `)
        return b`
            ${load(b`%args`, 1, b`%args`)}
        `.join(pieces)

    # XXX needs automatic bigint promotion
    c.function(b`Int`, ":object",
               ["i" => "l", "verb" => "l", "args" => ":list", "namedArgs" => "l"],
        go([
            ["add", 1] => b`
                ${getArgs([b`%j` => Int])}
                %i =l add %i, %j
                %rv =:object call $$makeObject(l $$Int, l %i)
                ret %rv
            `,
            ["next", 0] => b`
                %i =l add %i, 1
                %rv =:object call $$makeObject(l $$Int, l %i)
                ret %rv
            `,
            ["previous", 0] => b`
                %i =l sub %i, 1
                %rv =:object call $$makeObject(l $$Int, l %i)
                ret %rv
            `,
        ])
    )

def cspan(span :DeepFrozen, _ej) :Bytes as DeepFrozen:
    return b`# ${M.toString(span)}`

def compileMoar(compiler) as DeepFrozen:
    return object exprCompiler:
        to FinalPattern(name :Str, _guard, via (cspan) span):
            return fn specimen { b`
                $span
                %$name =l copy $specimen
            ` }

        to Atom(inner, _span):
            return inner

        to LiteralExpr(value, via (cspan) span):
            def l := compiler.prebuild(b`${M.toString(value._getAllegedInterface())}`, value)
            return fn rv { b`
                $span
                $rv =l copy $l
            ` }

        to NounExpr(name, via (cspan) span):
            return fn rv { b`
                $span
                $rv =l copy %$name
            ` }

        to MethodCallExpr(receiver, verb :Str, args, _namedArgs, via (cspan) span):
            def allocTemp := compiler.temp()
            def linkTemp := compiler.temp()
            def sizeTemp := compiler.temp()

            def receiverTemp := compiler.temp()
            def scriptTemp := compiler.temp()
            def closureTemp := compiler.temp()
            def receiverCode := receiver(receiverTemp) + b`
                $span: receiver
                $scriptTemp =l loadl $receiverTemp
                $receiverTemp =l add $receiverTemp, 8
                $closureTemp =l loadl $receiverTemp
            `

            def argList := compiler.temp()
            def argCode := b`
                $span: args
                $argList =l copy 0
                $sizeTemp =l copy 0
            ` + b``.join([for arg in (args.reverse()) {
                def argTemp := compiler.temp()
                arg(argTemp) + b`
                    $allocTemp =l alloc8 24
                    storel $argTemp, $allocTemp
                    $linkTemp =l add $allocTemp, 8
                    storel $argList, $linkTemp
                    $sizeTemp =l add $sizeTemp, 1
                    $linkTemp =l add $linkTemp, 8
                    storel $sizeTemp, $linkTemp
                    $argList =l copy $allocTemp
                `
            }])

            def messageTemp := compiler.temp()
            def messageCode := b`
                $span: message
                $messageTemp =l alloc8 24
                storel $messageTemp, ${compiler.constant(verb)}
                $linkTemp =l add $messageTemp, 8
                storel $linkTemp, $argList
            `
            return fn rv { receiverCode + argCode + messageCode + b`
                $span: call
                $rv =:object call $scriptTemp(l $closureTemp, l $messageTemp)
            ` }

        to LetExpr(patt, expr, body, _span):
            def exprTemp := compiler.temp()
            def pattCode := expr(exprTemp) + patt(exprTemp)
            return fn rv { pattCode + body(rv) }

def compile(c, expr) as DeepFrozen:
    return go(expr)(compileMoar(c))

def makeProgram(expr :DeepFrozen) :Bytes as DeepFrozen:
    var counter := 0
    def nameMaker() :Bytes:
        counter += 1
        return b`${M.toString(counter)}`
    def c := makeCompiler()
    makePrelude(c)
    def guts := compile(c, expr)(b`%obj`)
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
        $guts
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
