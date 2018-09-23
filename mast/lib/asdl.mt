import "lib/iterators" =~ [=> zip]
import "lib/pen" =~ [=> pk, => makeSlicer]
exports (runParser)

"The Zephyr Abstract Syntax Description Language."

# ftp://ftp.cs.princeton.edu/techreports/1997/554.pdf

object bootBuilder as DeepFrozen:
    to Sum(id, fields, con, cons):
        return object Sum {
            to _printOn(out) { out.print(`Sum($id, $fields, $con, $cons)`) }
            method run(f) {
                f.Sum(id, [for x in (fields) x(f)], con(f),
                      [for x in (cons) x(f)])
            }
        }
    to Product(ty, f, fs):
        return object Product {
            to _printOn(out) { out.print(`Product($ty, $f, $fs)`) }
            method run(runner) {
                f.Product(ty, f(runner), [for x in (fs) x(runner)])
            }
        }
    to Con(name, fs):
        return object Con {
            to _printOn(out) { out.print(`Con($name, $fs)`) }
            method run(f) { f.Con(name, [for x in (fs) x(f)]) }
        }
    to Id(ty, name):
        return object Id {
            to _printOn(out) { out.print(`Id($ty, $name)`) }
            method run(f) { f.Id(ty, name) }
        }
    to Option(ty, name):
        return object Option {
            to _printOn(out) { out.print(`Option($ty, $name)`) }
            method run(f) { f.Option(ty, name) }
        }
    to Sequence(ty, name):
        return object Sequence {
            to _printOn(out) { out.print(`Sequence($ty, $name)`) }
            method run(f) { f.Sequence(ty, name) }
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
                  id.optional()) % fn [[ty, deco], name] {
                    switch (deco) {
                        match ==null { builder.Id(ty, name) }
                        match =='?' { builder.Option(ty, name) }
                        match =='*' { builder.Sequence(ty, name) }
                    }
                  }
    def fields := field.joinedBy(comma).bracket(pk.string("("),
                                                pk.string(")") << ws)
    def constructor := (con_id + fields.optional()) % fn [name, fs] {
        builder.Con(name, fs)
    }
    def sum_type := constructor.joinedBy(pipe) + (
        (pk.string("attributes") >> fields) / pk.pure([]))
    def product_type := fields
    # Divergence from the original grammar in order to simplify AST-building;
    # we double up on `typ_id << equals`.
    def typ_eq := typ_id << equals
    def sum_definition := (typ_eq + sum_type) % fn [ty, [[con] + cons, attrs]] {
        builder.Sum(ty, attrs, con, cons)
    }
    def product_definition := (typ_eq + product_type) % fn [ty, [f] + fs] {
        builder.Product(ty, f, fs)
    }
    def definition := sum_definition / product_definition
    def definitions := definition.bracket(ws, ws).zeroOrMore()
    return definitions

def runParser(s :Str, ej) as DeepFrozen:
    def p := makeParser(bootBuilder)
    return p(makeSlicer.fromString(s), ej)

# Figure 15
def boot :Str := `
    asdl_ty = Sum(identifier, field*, constructor, constructor*)
            | Product(identifier, field, field*)
    constructor = Con(identifier, field*)
    field = Id(identifier, identifier?)
          | Option(identifier, identifier?)
          | Sequence(identifier, identifier?)
`

def [ast, _] := runParser(boot, null)

traceln(ast)

# XXX borrowed from lib/gadts, should move to where zip lives?
def transpose(l :List) as DeepFrozen:
    return _makeList.fromIterable(M.call(zip, "run", l, [].asMap()))

def makeBuilderMaker() as DeepFrozen:
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

    return object builderMaker:
        to run(tys):
            def [methodss, gs] := transpose([for ty in (tys) ty(builderMaker)])
            # XXX is there really not a flatmap somewhere?
            def methods := {
                def l := [].diverge()
                for ms in (methodss) { for m in (ms) { l.push(m) } }
                l.snapshot()
            }
            def script := astBuilder.Script(null, methods, [], null)
            def obj := astBuilder.ObjectExpr(null, mpatt`asdlBuilder`, null,
                                             [], script, null)
            def ast := astBuilder.SeqExpr(gs.with(obj), null)
            return eval(ast, safeScope)

        to Sum(id, fields, con, cons):
            # XXX fields
            def methods := [con] + cons
            def namePatt := makeNamePatt(id)
            def guard := m`interface $namePatt {}`
            return [methods, guard]
        to Product(ty, f, fs):
            throw("too lazy sorry")
        to Con(name, fs):
            def [exprs, patts, isSequences] := transpose(fs)
            def comma := m`out.print(", ")`
            def printer := m`to _printOn(out) {
                out.print(${astBuilder.LiteralExpr(name, null)})
                out.print("(")
                ${astBuilder.SeqExpr(
                    [comma].join([for e in (exprs) m`out.print($e)`]),
                null)}
                out.print(")")
            }`
            def visitors := [for i => expr in (exprs) {
                if (isSequences[i]) {
                    m`[for x in ($expr) x(f)]`
                } else { expr }
            }]
            def runner := m`method run(f) {
                ${astBuilder.MethodCallExpr(m`f`, name, visitors, [], null)}
            }`
            def script := astBuilder.Script(null, [printer, runner], [], null)
            def namePatt := astBuilder.FinalPattern(
                astBuilder.NounExpr(name, null), null, null)
            def body := astBuilder.ObjectExpr(null, namePatt, null, [],
                                              script, null)
            return astBuilder."Method"(null, name, patts, [], null, body, null)
        to Id(ty, name):
            def n := nextNoun(ty, name)
            # XXX astBuilder guard bug?
            def patt := astBuilder.FinalPattern(n, m`Any`, null)
            return [n, patt, false]
        to Option(ty, name):
            def n := nextNoun(ty, name)
            # XXX astBuilder substitution bug
            def patt := astBuilder.FinalPattern(n, m`NullOk`, null)
            return [n, patt, false]
        to Sequence(ty, name):
            def n := nextNoun(ty, name)
            def patt := astBuilder.FinalPattern(n, m`List`, null)
            return [n, patt, true]

def asdlBuilder := makeBuilderMaker()(ast)
traceln(asdlBuilder)

def runNewParser(s :Str, ej):
    def p := makeParser(asdlBuilder)
    return p(makeSlicer.fromString(s), ej)

traceln(runNewParser(boot, null))
