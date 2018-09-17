import "lib/pen" =~ [=> pk, => makeSlicer]
exports (runParser)

"The Zephyr Abstract Syntax Description Language."

# ftp://ftp.cs.princeton.edu/techreports/1997/554.pdf

def makeParser() as DeepFrozen:
    def buildId([x, xs]) { return _makeStr.fromChars([x] + xs) }
    # Figure 1
    def upper := pk.satisfies(('A'..'Z').contains)
    def lower := pk.satisfies(('a'..'z').contains)
    def alpha := pk.equals('_') / upper / lower
    def alpha_num := alpha / pk.satisfies(('0'..'9').contains)
    def typ_id := (lower + alpha_num.zeroOrMore()) % buildId
    def con_id := (upper + alpha_num.zeroOrMore()) % buildId
    def id := typ_id / con_id
    def field := typ_id + (pk.string("?") / pk.string("*")).optional() + id.optional()
    def fields := field.joinedBy(pk.string(",")).bracket(pk.string("("), pk.string(")"))
    def constructor := con_id + fields.optional()
    def sum_type := constructor.joinedBy(pk.string("|")) + (pk.string("attributes") >> fields).optional()
    def product_type := fields
    def type := sum_type / product_type
    def definitions := (typ_id + (pk.string("=") >> type)).zeroOrMore()
    return definitions

def runParser(s :Str, ej) as DeepFrozen:
    def p := makeParser()
    return p(makeSlicer.fromString(s), ej)
