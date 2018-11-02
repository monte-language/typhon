exports (main)

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

    return object compiler:
        to finish():
            return b`$\n`.join(pieces)

        to constant(value):
            return constCache.fetch(value, fn {
                def name := nameMaker("const")
                switch (value) {
                    match s :Str {
                        pieces.push(b`
                            data $$$name = { b${M.toQuote(s)}, b 0 }
                        `)
                    }
                }
                constCache[value] := name
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
        def tree := b`$\n`.join([for [verb, arity] => body in (script) {
            def marker := M.toString(counter)
            def isVerb := b`%isItVerb$marker`
            def cmpArity := b`%cmpArity$marker`
            def const := c.constant(verb)
            def len := M.toString(verb.size() + 1)
            # So inelegant.
            counter += 1
            b`
            @@checkVerbFor$marker
                $isVerb =w call $$memcmp(l %verb, l $$$const, w $len)
                jnz $isVerb, @@checkVerbFor${M.toString(counter)}, @@checkArityFor$marker
            @@checkArityFor$marker
                $cmpArity =w ceql %arity, ${M.toString(arity)}
                jnz $cmpArity, @@checkVerbFor${M.toString(counter)}, @@do$marker
            @@do$marker
            ` + body
        }])
        return b`
            %arity =l call $$listSize(:list %args)
        ` + tree + b`
        @@checkVerbFor${M.toString(counter)}
            # We are actually out of checks. So it is now time for failure.
            %_r =w call $$puts(l $$${c.constant("welp\n")})
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

def compile(compiler, expr :DeepFrozen, nameMaker) as DeepFrozen:
    def label := nameMaker()
    def name := b`_monte_block_$label`
    return switch (expr.getNodeName()) {
        match =="LiteralExpr" {
            switch (expr.getValue()) {
                match i :Int {
                    compiler.function(name, ":object", ["frame" => "l"], b`
                        %obj =:object call $$makeObject(l $$Int, l ${M.toString(i)})
                        ret %obj
                    `)
                    name
                }
            }
        }
        match =="MethodCallExpr" {
            def target := compile(compiler, expr.getReceiver(), nameMaker)
            def verb := compiler.constant(expr.getVerb())
            def argPairs := [for arg in (expr.getArgs()) {
                def n := compile(compiler, arg, nameMaker)
                def t := b`%_monte_method_arg_${nameMaker()}`
                [t, b`
                    $t =:object call $$$n(l %frame)
                `]
            }]
            def argAssigns := b`$\n`.join([for [_, assign] in (argPairs) assign])
            def argBuild := b`$\n`.join([for [t, _] in (argPairs.reverse()) {
                b`
                    %args =:list call $$makeCons(l $t, :list %args)
                `
            }])
            # We can stack-allocate messages because of the
            # no-stale-stack-frames rule.
            compiler.function(name, ":object", ["frame" => "l"], b`
                %target =:object call $$$target(l %frame)
                %script =l loadl %target
                %targetData =l add %target, 8
                %data =l loadl %targetData
                $argAssigns
                %args =l copy 0
                $argBuild
                %obj =:object call %script(l %data, l $$$verb, :list %args, l 0)
                ret %obj
            `)
            name
        }
    }

def makeProgram(expr :DeepFrozen) :Bytes as DeepFrozen:
    var counter := 0
    def nameMaker() :Bytes:
        counter += 1
        return b`${M.toString(counter)}`
    def c := makeCompiler()
    makePrelude(c)
    def name := compile(c, expr, nameMaker)
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
