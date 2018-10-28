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

    return object compiler:
        to finish():
            return b`$\n`.join(pieces)

        to constant(value):
            def name := nameMaker("const")
            switch (value):
                match s :Str:
                    pieces.push(b`
                        data $$$name = { b${M.toQuote(s)}, b 0 }
                    `)
            return name

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

def FAILURE :Bytes := b`0`
def INT :Bytes := b`1`
# def STR :Bytes := b`1`
# def LIST :Bytes := b`2`
# def MAP :Bytes := b`3`

def makePrelude(c) as DeepFrozen:
    c.function(b`makeObject`, ":object", ["tag" => "l", "data" => "l"], b`
        %p =l call $$calloc(w 2, w 8)
        storel %tag, %p
        %q =l add %p, 8
        storel %data, %q
        ret %p
    `)

    # XXX needs automatic bigint promotion
    c.function(b`intNext`, ":object", ["i" => "l"], b`
        %i =l add %i, 1
        %obj =:object call $$makeObject(l $INT, l %i)
        ret %obj
    `)

    c.function(b`intCallMessage`, ":object",
                      ["i" => "l", "message" => ":message"], b`
        %verb =l loadl %message
        %diff =w call $$memcmp(l %verb, l $$${c.constant("next")}, w 5)
        jnz %diff, @@fail, @@next
    @@next
        %rv =:object call $$intNext(l %i)
        ret %rv
    @@fail
        ret $$theFailure
    `)

    c.function(b`MCallMessage`, ":object",
                      ["obj" => ":object", "message" => ":message"], b`
        %tag =l loadl %obj
        %p =l add %obj, 8
        %data =l loadl %p
        jnz %tag, @@int, @@fail
    @@fail
        ret $$theFailure
    @@int
        %rv =:object call $$intCallMessage(l %data, :message %message)
        ret %rv
    `)

def compile(compiler, expr :DeepFrozen, nameMaker) as DeepFrozen:
    def label := nameMaker()
    def name := b`_monte_block_$label`
    return switch (expr.getNodeName()) {
        match =="LiteralExpr" {
            switch (expr.getValue()) {
                match i :Int {
                    compiler.function(name, ":object", ["frame" => "l"], b`
                        %obj =:object call $$makeObject(l $INT, l ${M.toString(i)})
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
                %message =l alloc8 24
                storel $$$verb, %message
                %obj =:object call $$MCallMessage(:object %target, :message %message)
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
    data $$theFailure = { l $FAILURE, l 0 }
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
        %isInt =w ceql %tag, $INT
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
    def expr := m`41.next()`
    def program := makeProgram(expr)
    return when (stdout<-(program)) ->
        when (stdout<-complete()) -> { 0 }
