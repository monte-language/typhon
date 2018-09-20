import "lib/pen" =~ [=> pk, => makeSlicer]
exports (runParser)

"The Zephyr Abstract Syntax Description Language."

# ftp://ftp.cs.princeton.edu/techreports/1997/554.pdf

def makeParser() as DeepFrozen:
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
                        match ==null { ["Id", ty, name] }
                        match =='?' { ["Option", ty, name] }
                        match =='*' { ["Sequence", ty, name] }
                    }
                  }
    def fields := field.joinedBy(comma).bracket(pk.string("("),
                                                pk.string(")") << ws)
    def constructor := (con_id + fields.optional()) % fn [name, fs] {
        ["Con", name, fs]
    }
    def sum_type := constructor.joinedBy(pipe) + (pk.string("attributes") >> fields).optional()
    def product_type := fields
    def type := sum_type / product_type
    def definitions := (typ_id + (equals >> type)).bracket(ws, ws).zeroOrMore()
    return definitions

def runParser(s :Str, ej) as DeepFrozen:
    def p := makeParser()
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

escape ej:
    traceln(runParser(boot, ej))
catch problem:
    traceln(problem)
