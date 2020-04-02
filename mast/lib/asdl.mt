import "lib/freezer" =~ [=> freeze]
import "lib/pen" =~ [=> pk, => makeSlicer]
exports (asdlBuilder, buildASDLModule)

"The Zephyr Abstract Syntax Description Language."

# ASDL:
# ftp://ftp.cs.princeton.edu/techreports/1997/554.pdf

# The two styles of recursion we generate are related to:
# http://okmij.org/ftp/tagless-final/course/Boehm-Berarducci.html

object bootBuilder as DeepFrozen:
    to Sum(id :Str, fields :List[DeepFrozen], con :DeepFrozen,
           cons :DeepFrozen):
        return object Sum as DeepFrozen {
            to _printOn(out) { out.print(`Sum($id, $fields, $con, $cons)`) }
            method run(f) {
                f.Sum(id, [for x in (fields) x(f)], con(f),
                      [for x in (cons) x(f)])
            }
            method walk(f) { f.Sum(id, fields, con, cons) }
        }
    to Con(name :Str, fs :List[DeepFrozen]):
        return object Con as DeepFrozen {
            to _printOn(out) { out.print(`Con($name, $fs)`) }
            method run(f) { f.Con(name, [for x in (fs) x(f)]) }
            method walk(f) { f.Con(name, fs) }
        }
    to Id(ty :Str, name :NullOk[Str]):
        return object Id as DeepFrozen {
            to _printOn(out) { out.print(`Id($ty, $name)`) }
            method run(f) { f.Id(ty, name) }
            method walk(f) { f.Id(ty, name) }
        }
    to Option(ty :Str, name :NullOk[Str]):
        return object Option as DeepFrozen {
            to _printOn(out) { out.print(`Option($ty, $name)`) }
            method run(f) { f.Option(ty, name) }
            method walk(f) { f.Option(ty, name) }
        }
    to Sequence(ty :Str, name :NullOk[Str]):
        return object Sequence as DeepFrozen {
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
    # Divergence from the original grammar in order to simplify AST-building;
    # we double up on `typ_id << equals`.
    def typ_eq := typ_id << equals
    def definition := (typ_eq + sum_type + attribs) % fn [[ty, [con] + cons], attrs] {
        builder.Sum(ty, attrs, con, cons)
    }
    def definitions := definition.bracket(ws, ws).zeroOrMore()
    return definitions

def parseBootFragment(s :Str) as DeepFrozen:
    def p := makeParser(bootBuilder)
    def [rv, tail] := p(makeSlicer.fromString(s), null)
    escape tailtest:
        def next := tail.next(tailtest)
        throw(`Junk trying to boot ASDL parser: $next`)
    return rv

# Figure 15
# We don't do products. They're usually not what is wanted, and they
# complicate the compiler. ~ C.
def boot :Str := `
    asdl_ty = Sum(identifier, field*, constructor, constructor*)
    constructor = Con(identifier, field*)
    field = Id | Option | Sequence attributes (identifier, identifier?)
`

def bindingFragment :Str := `
    var = Var(str name)
    lam = Lam(var binding, df body)
`

def ast :DeepFrozen := parseBootFragment(boot)
def bindingClauses :DeepFrozen := parseBootFragment(bindingFragment)

def comma :DeepFrozen := m`out.print(", ")`

# Traditional ASDL has three types: identifier, int, str
# We extend this with a type for DF objects, as well as other Monte
# primitive types.
def theTypeGuards :Map[Str, DeepFrozen] := [
    "bool" => m`Bool`,
    "df" => m`DeepFrozen`,
    "double" => m`Double`,
    "identifier" => m`Str`,
    "int" => m`Int`,
    "str" => m`Str`,
]
def isPrimitive :DeepFrozen := theTypeGuards.getKeys().contains

def makeBuilderMaker(builderName :DeepFrozen, addBindings :Bool) as DeepFrozen:
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

    # The methods for building each constructor.
    def methods := [].diverge()

    # The raw constructor atoms, used for error messages.
    def atoms := [].asMap().diverge()

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
            def exprs := [].diverge()
            def patts := [].diverge()
            def visitors := [].diverge()

            object fieldWalker:
                match [verb, [ty, name], _]:
                    def tyGuard := theTypeGuards.fetch(ty, fn {
                        astBuilder.NounExpr("_sum_guard_" + ty, null)
                    })
                    def g := fieldGuards[verb](tyGuard)
                    exprs.push(def n := nextNoun(ty, name))
                    # XXX Monte parser bug; mpatt`$n :$g` should work.
                    patts.push(astBuilder.FinalPattern(n, g, null))
                    visitors.push(if (isPrimitive(ty)) { n } else {
                        fieldVisitors[verb](n)
                    })
                    null

            atoms[name] := fs.size() + attributeFields.size()
            for f in (fs + attributeFields):
                f.walk(fieldWalker)

            def printer := m`to _printOn(out) {
                out.print(${astBuilder.LiteralExpr(name, null)})
                out.print("(")
                ${astBuilder.SeqExpr(
                    [comma].join([for e in (exprs.snapshot()) m`out.print($e)`]),
                null)}
                out.print(")")
            }`
            def runner := m`method run(f) {
                "
                Rewrite this term, bottom-up, over ``f``.

                This term's components will be visited, and then this term;
                each argument will have already been rewritten.
                "
                ${astBuilder.MethodCallExpr(m`f`, name, visitors.snapshot(), [], null)}
            }`
            def walker := m`method walk(f) {
                "
                Take one rewriting step of this term over ``f``.

                This term's components will not be visited automatically;
                ``f`` is responsible for any recursive actions.
                "
                ${astBuilder.MethodCallExpr(m`f`, name, exprs.snapshot(), [], null)}
            }`
            def script := astBuilder.Script(null, [printer, runner, walker], [], null)
            def namePatt := astBuilder.FinalPattern(
                astBuilder.NounExpr(name, null), null, null)
            def body := astBuilder.ObjectExpr(null, namePatt, m`DeepFrozen`,
                                              [conGuard], script, null)
            def rv := astBuilder."Method"(null, name, patts.snapshot(), [], null, body, null)
            methods.push(rv)

    return def builderMaker(var tys):
        # These statements will run before we define our builder.
        def preamble := [
            m`def DF :Same[DeepFrozen] := DeepFrozen`
        ].diverge()

        # If ABTs are enabled, mix in the ABT clauses.
        if (addBindings):
            tys += bindingClauses

        for ty in (tys):
            ty.walk(def tyWalker.Sum(id :Str, fields, con, cons) {
                atoms[id] := fields.size()
                def idName := astBuilder.NounExpr(id, null)
                def sumGuard := astBuilder.NounExpr("_sum_guard_" + id, null)
                def sumStamp := astBuilder.NounExpr("_sum_stamp_" + id, null)
                def sumGuardPatt := astBuilder.FinalPattern(sumGuard,
                                                            m`DeepFrozen`,
                                                            null)
                def sumStampPatt := astBuilder.FinalPattern(sumStamp,
                                                            m`DeepFrozen`,
                                                            null)
                def decl := m`def [$sumGuardPatt, $sumStampPatt] := {
                    interface ISum :DF guards SumStamp :DF {}
                    [object $idName extends ISum as DF implements SubrangeGuard[DF] {
                        to coerce(specimen, ej) :DF {
                            return ISum.coerce(specimen, ej)
                        }
                    }, SumStamp]
                }`
                preamble.push(decl)
                methods.push(m`to $id() { return $sumGuard }`)
                def conWalker := makeConWalker(sumStamp, fields)
                for c in ([con] + cons) { c.walk(conWalker) }
            })
        preamble.push(m`def atoms :DeepFrozen := ${freeze(atoms.snapshot())}`)
        def friendly := m`match [verb, args, _] {
            def message := escape ej {
                def len := atoms.fetch(verb, fn {
                    ej(``This builder doesn't know constructor $$verb``)
                })
                ``Constructor $$verb needs $$len fields, not $${args.size()}``
            }
            throw(message)
        }`
        def script := astBuilder.Script(null, methods.snapshot(), [friendly],
                                        null)
        def builderPatt := astBuilder.FinalPattern(builderName, null, null)
        def obj := astBuilder.ObjectExpr(null, builderPatt, m`DeepFrozen`,
                                         [], script, null)
        # To be eval'd in safeScope.
        return astBuilder.SeqExpr(preamble.with(obj), null)

def asdlBuilder :DeepFrozen := makeBuilderMaker(m`asdlBuilder`, false)(ast)

def buildASDLModule(s :Str, petname :Str) :DeepFrozen as DeepFrozen:
    def p := makeParser(asdlBuilder)
    def [ast, tail] := p(makeSlicer.fromString(s), null)
    escape tailtest:
        def next := tail.next(tailtest)
        throw(`parser found junk at the end: $next`)
    def plainName := astBuilder.NounExpr(petname + "ASTBuilder", null)
    def plainPatt := astBuilder.FinalPattern(plainName, null, null)
    def withBindingsName := astBuilder.NounExpr(petname + "ABTBuilder", null)
    def withBindingsPatt := astBuilder.FinalPattern(withBindingsName, null, null)
    def plain := makeBuilderMaker(plainName, false)(ast)
    def withBindings := makeBuilderMaker(withBindingsName, true)(ast)
    def module := m`object _ {
        to dependencies() { return [] }
        to run(_) {
            def $plainPatt := { $plain }
            def $withBindingsPatt := { $withBindings }
            return [
                => $plainName,
                => $withBindingsName,
            ]
        }
    }`
    return module
