import "lib/pen" =~ [=> pk, => makeSlicer]
exports (asdlParser, asdlBuilder)

"The Zephyr Abstract Syntax Description Language."

# ASDL:
# ftp://ftp.cs.princeton.edu/techreports/1997/554.pdf

# The two styles of recursion we generate are related to:
# http://okmij.org/ftp/tagless-final/course/Boehm-Berarducci.html

object bootBuilder as DeepFrozen:
    to Sum(id, fields, con, cons):
        return object Sum {
            to _printOn(out) { out.print(`Sum($id, $fields, $con, $cons)`) }
            method run(f) {
                f.Sum(id, [for x in (fields) x(f)], con(f),
                      [for x in (cons) x(f)])
            }
            method walk(f) { f.Sum(id, fields, con, cons) }
        }
    to Product(ty, f, fs):
        return object Product {
            to _printOn(out) { out.print(`Product($ty, $f, $fs)`) }
            method run(runner) {
                f.Product(ty, f(runner), [for x in (fs) x(runner)])
            }
            method walk(walker) { walker.Product(ty, f, fs) }
        }
    to Con(name, fs):
        return object Con {
            to _printOn(out) { out.print(`Con($name, $fs)`) }
            method run(f) { f.Con(name, [for x in (fs) x(f)]) }
            method walk(f) { f.Con(name, fs) }
        }
    to Id(ty, name):
        return object Id {
            to _printOn(out) { out.print(`Id($ty, $name)`) }
            method run(f) { f.Id(ty, name) }
            method walk(f) { f.Id(ty, name) }
        }
    to Option(ty, name):
        return object Option {
            to _printOn(out) { out.print(`Option($ty, $name)`) }
            method run(f) { f.Option(ty, name) }
            method walk(f) { f.Option(ty, name) }
        }
    to Sequence(ty, name):
        return object Sequence {
            to _printOn(out) { out.print(`Sequence($ty, $name)`) }
            method run(f) { f.Sequence(ty, name) }
            method walk(f) { f.Sequence(ty, name) }
        }

def makeParser(builder) as DeepFrozen:
    def buildId([x, xs]) { return _makeStr.fromChars([x] + xs) }

    def ws := pk.satisfies(" \n".contains).zeroOrMore()
    def comma := pk.equals(',') << ws
    def equals := pk.equals('=').bracket(ws, ws)
    def pipe := pk.equals('|').bracket(ws, ws)

    # Figure 1
    def upper := pk.satisfies(('A'..'Z').contains)
    def lower := pk.satisfies(('a'..'z').contains)
    def alpha := pk.equals('_') / upper / lower
    def alpha_num := alpha / pk.satisfies(('0'..'9').contains)
    def typ_id := (lower + alpha_num.zeroOrMore()) % buildId
    def con_id := (upper + alpha_num.zeroOrMore()) % buildId
    def id := typ_id / con_id
    def field := (typ_id + pk.satisfies("*?".contains).optional() +
                  (ws >> id.optional())) % fn [[ty, deco], name] {
                    switch (deco) {
                        match ==null { builder.Id(ty, name) }
                        match =='?' { builder.Option(ty, name) }
                        match =='*' { builder.Sequence(ty, name) }
                    }
                  }
    def fields := field.joinedBy(comma).bracket(pk.string("("),
                                                pk.string(")"))
    def constructor := (con_id + fields.optional()) % fn [name, fs] {
        builder.Con(name, if (fs == null) { [] } else { fs })
    }
    # Divergence from the original grammar: Factor attributes.
    def attribKeyword := ws >> pk.string("attributes") << ws
    def attribs := (attribKeyword >> fields) / pk.pure([])
    def sum_type := constructor.joinedBy(pipe)
    def product_type := fields
    # Divergence from the original grammar in order to simplify AST-building;
    # we double up on `typ_id << equals`.
    def typ_eq := typ_id << equals
    def sum_definition := (typ_eq + sum_type + attribs) % fn [[ty, [con] + cons], attrs] {
        builder.Sum(ty, attrs, con, cons)
    }
    def product_definition := (typ_eq + product_type) % fn [ty, [f] + fs] {
        builder.Product(ty, f, fs)
    }
    def definition := sum_definition / product_definition
    def definitions := definition.bracket(ws, ws).zeroOrMore()
    return definitions

def bootParser(s :Str, ej) as DeepFrozen:
    def p := makeParser(bootBuilder)
    return p(makeSlicer.fromString(s), ej)

# Figure 15
def boot :Str := `
    asdl_ty = Sum(identifier, field*, constructor, constructor*)
            | Product(identifier, field, field*)
    constructor = Con(identifier, field*)
    field = Id | Option | Sequence attributes (identifier, identifier?)
`

def [ast, tail] := bootParser(boot, null)
escape tailtest:
    def next := tail.next(tailtest)
    throw(`Junk trying to boot ASDL parser: $next`)

# Traditional ASDL has three types: identifier, int, str
def isPrimitive :DeepFrozen := ["bool", "df", "identifier", "int", "str"].contains
def comma :DeepFrozen := m`out.print(", ")`

def gatherTys(tys :List) as DeepFrozen:
    def sumTys := [].diverge()
    def prodTys := [].diverge()

    for ty in (tys):
        ty.walk(object tyGatherer {
            to Product(ty, _f, _fs) { prodTys.push(ty) }
            to Sum(id, _fields, _con, _cons) { sumTys.push(id) }
        })

    return [sumTys, prodTys]

def makeBuilderMaker(builderName :DeepFrozen) as DeepFrozen:
    var count :Int := 0
    def nextName(prefix :Str) :Str:
        count += 1
        return `_${prefix}_$count`
    def nextNoun(ty :Str, name :NullOk[Str]) :DeepFrozen:
        return astBuilder.NounExpr(if (name == null) {
                                       nextName(ty)
                                   } else { name }, null)
    def makeNamePatt(name :Str) :DeepFrozen:
        return astBuilder.FinalPattern(
            astBuilder.NounExpr(name, null), null, null)

    def products := [].asMap().diverge()
    def methods := [].diverge()

    def typeGuards := [
        "bool" => m`Bool`,
        "df" => m`DeepFrozen`,
        "identifier" => m`Str`,
        "int" => m`Int`,
        "str" => m`Str`,
    ].diverge()

    def fieldGuards := [
        "Id" => fn g { g },
        "Option" => fn g { m`NullOk[$g]` },
        "Sequence" => fn g { m`List[$g]` },
    ]

    def fieldVisitors := [
        "Id" => fn n { m`$n(f)` },
        "Option" => fn n { m`if ($n != null) { $n(f) }` },
        "Sequence" => fn n { m`[for x in ($n) x(f)]` },
    ]

    def makeConWalker(conGuard, attributeFields):
        return def walker.Con(name, fs):
            # traceln(`Con($name, $fs)`)
            def exprs := [[].diverge()].diverge()
            def patts := [[].diverge()].diverge()
            def visitors := [[].diverge()].diverge()

            object fieldWalker:
                match [verb, [ty, name], _]:
                    if (products.contains(ty)):
                        for l in ([exprs, patts, visitors]):
                            l.push([].diverge())
                        for field in (products[ty]):
                            field.walk(fieldWalker)
                        def es := astBuilder.ListExpr(exprs.pop().snapshot(), null)
                        exprs.last().push(es)
                        def ps := astBuilder.ListPattern(patts.pop().snapshot(), null, null)
                        patts.last().push(ps)
                        def vs := astBuilder.ListExpr(visitors.pop().snapshot(), null)
                        visitors.last().push(vs)
                    else:
                        def tyGuard := typeGuards[ty]
                        def g := fieldGuards[verb](tyGuard)
                        exprs.last().push(def n := nextNoun(ty, name))
                        # XXX astBuilder guard bug?
                        patts.last().push(astBuilder.FinalPattern(n, g, null))
                        visitors.last().push(if (isPrimitive(ty)) { n } else {
                            fieldVisitors[verb](n)
                        })
                    null

            for f in (fs + attributeFields):
                f.walk(fieldWalker)

            def printer := m`to _printOn(out) {
                out.print(${astBuilder.LiteralExpr(name, null)})
                out.print("(")
                ${astBuilder.SeqExpr(
                    [comma].join([for e in (exprs.last()) m`out.print($e)`]),
                null)}
                out.print(")")
            }`
            def runner := m`method run(f) {
                ${astBuilder.MethodCallExpr(m`f`, name, visitors.last().snapshot(), [], null)}
            }`
            def walker := m`method walk(f) {
                ${astBuilder.MethodCallExpr(m`f`, name, exprs.last().snapshot(), [], null)}
            }`
            def script := astBuilder.Script(null, [printer, runner, walker], [], null)
            def namePatt := astBuilder.FinalPattern(
                astBuilder.NounExpr(name, null), null, null)
            def body := astBuilder.ObjectExpr(null, namePatt, conGuard, [],
                                              script, null)
            def rv := astBuilder."Method"(null, name, patts.last().snapshot(), [], null, body, null)
            methods.push(rv)

    return def builderMaker(tys):
        # These statements will run before we define our builder.
        def preamble := [].diverge()

        def [sumTys, prodTys] := gatherTys(tys)
        for sumTy in (sumTys):
            def sumGuard := astBuilder.NounExpr("_sum_type_" + sumTy, null)
            def sumPatt := astBuilder.FinalPattern(sumGuard, m`DeepFrozen`,
                                                    null)
            preamble.push(m`interface $sumPatt {}`)
            typeGuards[sumTy] := sumGuard
        for prodTy in (prodTys):
            typeGuards[prodTy] := m`List`

        for ty in (tys):
            ty.walk(object tyWalker {
                to Sum(id, fields, con, cons) {
                    def nameNoun := typeGuards[id]
                    def conWalker := makeConWalker(nameNoun, fields)
                    for c in ([con] + cons) { c.walk(conWalker) }
                }
                to Product(ty, f, fs) { products[ty] := [f] + fs }
            })
        def script := astBuilder.Script(null, methods.snapshot(), [], null)
        def obj := astBuilder.ObjectExpr(null, builderName, m`DeepFrozen`,
                                         [], script, null)
        def ast := astBuilder.SeqExpr(preamble.with(obj), null)
        return eval(ast, safeScope)

def asdlBuilder :DeepFrozen := makeBuilderMaker(mpatt`asdlBuilder`)(ast)

def asdlParser(builderName :DeepFrozen, s :Str, ej) :DeepFrozen as DeepFrozen:
    "Parse a string into an AST builder."

    def p := makeParser(asdlBuilder)
    def [ast, tail] := p(makeSlicer.fromString(s), ej)
    escape tailtest:
        def next := tail.next(tailtest)
        throw.eject(ej, `parser found junk at the end: $next`)
    return makeBuilderMaker(builderName)(ast)
