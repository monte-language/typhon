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

    def go(script):
        # Inelegant hack: We can't get a standard loop counter here, so we do
        # it by hand and deliberately make it cheap to compute the following
        # counter value (+1) in order to avoid running the loop twice. ~ C.
        var counter :Int := 0
        return b`$\n`.join([for verb => body in (script) {
            def marker := M.toString(counter)
            def is := b`%isItVerb$marker`
            def const := c.constant(verb)
            def len := M.toString(verb.size() + 1)
            b`
            @@checkFor$marker
                $is =w call $$memcmp(l %verb, l $$$const, w $len)
                jnz $is, @@do$marker, @@checkFor${M.toString(counter += 1)}
            @@do$marker
            ` + body
        }]) + b`
        @@checkFor${M.toString(counter)}
            # We are actually out of checks. So it is now time for failure.
            ret $$theFailure
        `

    c.function(b`Int`, ":object",
               ["i" => "l", "verb" => "l", "args" => "l", "namedArgs" => "l"],
        go([
            "next" => b`
                # XXX needs automatic bigint promotion
                %i =l add %i, 1
                %rv =:object call $$makeObject(l $$Int, l %i)
                ret %rv
            `,
            "previous" => b`
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
            # We can stack-allocate messages because of the
            # no-stale-stack-frames rule.
            compiler.function(name, ":object", ["frame" => "l"], b`
                %target =:object call $$$target(l %frame)
                %script =l loadl %target
                %targetData =l add %target, 8
                %data =l loadl %targetData
                %obj =:object call %script(l %data, l $$$verb, l 0, l 0)
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
    # { l %tag, l %data }
    type :object = { l, l }

    # { l %verb, l %args, l %namedArgs }
    type :message = { l, l, l }
    data $$theFailure = { l 0, l 0 }
    ` + c.finish() + b`
    data $$hello = { b"Hello from compiled native Monte!", b 0 }
    data $$landing = { b"Stuck the landing?", b 0 }
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
    def expr := m`42.previous().next()`
    def program := makeProgram(expr)
    return when (stdout<-(program)) ->
        when (stdout<-complete()) -> { 0 }
