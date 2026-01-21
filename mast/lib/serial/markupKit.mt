import "unittest" =~ [=> unittest]
import "lib/codec/utf8" =~ [=>UTF8 :DeepFrozen]
import "guards" =~ [=>Tuple :DeepFrozen]
import "./elib/serial/DEBuilderOf" =~ [=> DEBuilderOf :DeepFrozen]
exports (main, Name, nameStart, nameChar, Element, Text, deMarkupKit)


def oneOf(chars :DeepFrozen) as DeepFrozen:
    "String matching guard builder with utilities.

    chars may be anything with a .contains(ch :Char) method.
    "
    return object oneOf as DeepFrozen:
        to coerce(specimen, ej):
            if (!chars.contains(specimen)):
                ej(`found $specimen when expecting $chars`)
            return specimen

        to add(rest :DeepFrozen):
            "Prefix this guard to a string guard.

            e.g. oneOf(nameStart) + oneOf(nameChar).star()
            "
            return def concat.coerce(specimen, ej) as DeepFrozen:
                Str.coerce(specimen, ej)
                oneOf.coerce(specimen[0], ej)
                rest.coerce(specimen.slice(1), ej)
                return specimen

        to star():
            "Repeat any nuber of times (Kleene-star).
            "
            return def repeat.coerce(specimen, ej) as DeepFrozen:
                for ch in (specimen):
                    oneOf.coerce(ch, ej)
                return specimen

        to plus():
            "One or more repetitions.

            def word := oneOf('a'..'z').plus()
            "
            return oneOf + oneOf.star()

        to findFirst(s :Str) :Tuple[Str, NullOk[Char], Str]:
            "Find the first of these characters to occur.
            "
            var out :Tuple[Str, NullOk[Char], Str] := [s, null, ""]

            for delim in (chars):
                if (s.split(delim.asString(), 1) =~ [pre, post] && pre.size() < out[0].size()):
                    out := [pre, delim, post]
            return out

        to split(s :Str, "max"=>max :NullOk[Int>0] := null) :List[Str]:
            "(split is dead code, but it's tested, working dead code!)
            "
            def out := [].diverge()
            var piece :Int := 0
            var sep :Int := -1
            for ix => ch in (s):
                switch ([chars.contains(ch), sep > piece]) {
                    match ==[true, true]   { }
                    match ==[false, false] { }
                    match [==true, _] {
                        out.push(s.slice(piece, ix))
                        sep := ix
                    }
                    match [_, ==true] {
                        piece := ix
                        if (max != null && out.size() >= max) {
                            break
                        }
                        sep := -1
                    }
                }
            if (piece > sep) {
                out.push(s.slice(piece))
            }
            return out.snapshot()
                    
def oneOfTest(assert) as DeepFrozen:
    for [s, delim, m, expected] in ([
        ["", [], null, [""]],
        ["a   b c", [' '], null, ["a", "b", "c"]],
        ["a \n  b c", [' ', '\n'], null, ["a", "b", "c"]],
        ["a   b c", [' '], 1, ["a", "b c"]]
    ]):
        assert.equal(oneOf(delim).split(s, "max"=>m), expected)

    for [s, delim, expected] in ([
        ["blah bla <b>spif", ['<', '&'], ["blah bla ", '<', "b>spif"]],
        ["blah &bla <b>spif", ['<', '&'], ["blah ", '&', "bla <b>spif"]],
        ["blah <bla <b>&spif", ['<', '&'], ["blah ", '<', "bla <b>&spif"]],
        ["", [], ["", null, ""]],
    ]):
        assert.equal(oneOf(delim).findFirst(s), expected)


########
# A Name is a Str consisting of a nameStart followed by any number of nameChar.

# TODO: non-ASCII stuff from https://www.w3.org/TR/xml/#NT-Name
# [4] NameStartChar	   ::=   	":" | [A-Z] | "_" | [a-z] |
#                   [#xC0-#xD6] | [#xD8-#xF6] | [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] |
#                   [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] |
#                   [#xF900-#xFDCF] | [#xFDF0-#xFFFD] | [#x10000-#xEFFFF]
# [4a] NameChar	   ::=   	NameStartChar | "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]
# [5]  Name	   ::=   	NameStartChar (NameChar)*

def nameStart :DeepFrozen := ':'..':' | 'A'..'Z' | '_'..'_' | 'a'..'z' 
def nameChar :DeepFrozen := nameStart | '-'..'-' | '.'..'.' | '0'..'9'


def Name :DeepFrozen := oneOf(nameStart) + oneOf(nameChar).star()

def nameTests(assert) as DeepFrozen:
    for n in (["p", "h1"]):
        assert.equal(n :Name, n)
    for s in (["x y", "", "23", "<p>", "&lt;"]):
        assert.throws(fn { s :Name })


# hmm... some characters not allowed, right?
def Text :DeepFrozen := Str


##########
# MLReader cf. SAX

def makeMLReader(handler,
                 =>ws := [' ', '\n'],
                 =>selfClosing := [
                     # HTML 4
                     "area", "base", "br", "col", "hr", "img", "input", "link", "meta", "param",
                     # HTML 5
                     "command", "keygen", "source"],
                 =>entities := ["amp"=>"&", "lt"=>"<", "gt"=>">", "quot"=>"\"", "apos"=>"'"]) as DeepFrozen {
    def Numeral := oneOf('0'..'9').plus()

    def tryEntity(ampPost :Text, thunk) :Int {
        return if (ampPost =~ `#@{charCode :Numeral};@_rest`) {
            def ch := ('\x00' + _makeInt(charCode)).asString()
            thunk(ch)
            charCode.size() + 2
        } else if (ampPost =~ `@{entityName :Name ? (entities.contains(entityName))};@_rest`) {
            thunk(entities[entityName])
            entityName.size() + 2
        } else {
            thunk("&")
            0
        }
    }

    def makeTag(ltPost :Text) {
        var ix :Int := 0
        var ch := null
        def advance() {
            return if (ix < ltPost.size()) {
                ch := ltPost[ix]
                ix += 1
                true
            } else {
                ch := null
                false
            }
        }
        advance()

        def skipSpace() {
            while (ws.contains(ch) && advance()) {  }
        }
        def expect(fail, options) {
            if (options.contains(ch)) {
                advance()
            } else {
                traceln(`expect($options) got $ch`)
                fail(ix)
            }
        }
        def name(fail) {
            def start := ix - 1
            expect(fail, nameStart)
            while(nameChar.contains(ch) && advance()) { }
            def out := ltPost.slice(start, ix - 1)
            skipSpace()
            # traceln(`name: ltPost[$start..$ix] = $out`)
            return out
        }
        def attribute(fail) {
            def attrName := name(fail)
            skipSpace()
            expect(fail, ['='])
            skipSpace()
            def delim := ch
            expect(fail, ['\'', '"'])
            var value :Str := ""
            while (ch != delim) {
                if (ch == '&') {
                    ix += tryEntity(ltPost.slice(ix), fn s { value += s}) - 1
                } else {
                    value += ch.asString()
                }
                if (!advance()) { break }
            }
            advance()
            skipSpace()
            return [attrName, value]
        }

        return object tag {
            to start() :Text {
                escape badTag {
                    def tagName := name(badTag)
                    def attrs := [].diverge()
                    while (nameStart.contains(ch)) {
                        attrs.push(attribute(badTag))
                    }
                    handler.startElement(tagName, _makeMap.fromPairs(attrs))
                    # XML-ish mode
                    if (selfClosing.size() == 0) {
                        if (ch == '/') {
                            expect(badTag, ['>'])
                            handler.endElement(tagName)
                        } else {
                            expect(badTag, ['>'])
                        }
                    } else {
                        if (ch == '/') { advance() }
                        expect(badTag, ['>'])
                        # traceln(`got tag to $ix: $tagName $attrs`)
                        if (selfClosing.contains(tagName)) {
                            handler.endElement(tagName)
                        }
                    }
                } catch errIx {
                    handler.error([ltPost, errIx])
                }

                return ltPost.slice(ix - 1)
            }
            to end() :Text {
                escape badTag {
                    expect(badTag, ['/'])
                    def tagName := name(badTag)
                    expect(badTag, ['>'])
                    handler.endElement(tagName)
                } catch errIx {
                    handler.error([ltPost, errIx])
                }

                return ltPost.slice(ix - 1)
            }
        }
    }

    return def XMLReader.parse(var markup :Text) :Void {
        while(markup.size() > 0) {
            def [text, delim, rest] := oneOf(['<', '^']).findFirst(markup)
            if (text.size() > 0) {
                handler.characters(text)
            }

            # traceln(`M:${markup.slice(0, 4)}... => ${[text, delim, rest]}`)
            switch (delim) {
                match ==null { markup := "" }
                match =='&' { markup := rest.slice(tryEntity(rest, handler.characters)) }
                match =='<' {
                    markup := if (rest == "") {
                        handler.characters("<")
                        ""
                    } else if (rest[0] == '/') {
                        makeTag(rest).end()
                    } else if (nameStart.contains(rest[0])) {
                        makeTag(rest).start()
                    } else if (rest =~ `!--@comment-->@more`) {
                        handler.comment(comment)
                        more
                    } else if (rest.slice(0, "!doctype".size()).toLowerCase() == "!doctype" &&
                               (def after := rest.slice("!doctype".size())).contains(">")) {
                        def `@decl>@more` := after
                        handler.doctype(decl)
                        more
                    } else {
                        handler.characters("<")
                        rest
                    }
                }
            }
        }
    }
}


###
# Element data

# TODO. postponed due to:
# ~ Problem: Message refused: (<NamedParam>).getNodeName()
# ~   <NamedParam>.getNodeName()
# deep inside  <astBuilder>.convertFromKernel(<Obj>)
# def [makerAuditor :DeepFrozen, &&Element, &&serializer] := Transparent.makeAuditorKit()

interface Element :DeepFrozen {}

def Content :DeepFrozen := Any[Element, Text, List[Any[Element, Text]]]

def makeElement(tag :Name,
                "attrs"=>attrs :Map[Name, Str] := [].asMap(),
                "children"=>children :NullOk[List[Content]] := []) as DeepFrozen:
    return object element implements Selfless, Element:
        to _uncall():
            # return serializer(makeElement, tag, "attrs"=>attrs, "children"=>children)
            return [makeElement, "run", [tag], ["attrs"=>attrs, "children"=>children]]

        to getAttr(name :Name, =>FAIL):
            return attrs.fetch(name, FAIL)

        to _printOn(p):
            p.print(`<$tag`)
            for n => v in (attrs):
                p.print(` $n="$v"`)   #@@ TODO: fix markup in v
            if (children == null):
                p.print(" />")
            else:
                p.print(">")
                for ch in (children):
                    ch._printOn(p)
                p.print(`</$tag>`)


object deMarkupKit as DeepFrozen {
    to makeBuilder() {
        return object deMarkupBuilder implements DEBuilderOf[Str, Str] {
            to buildRoot(root :Str) :Str { return root }
            to buildLiteral(text :Text) :Content { return text }
            to buildImport(varName :Str) :Str {
                return makeElement("a", "attrs"=>["href"=>varName, "class"=>"import"],
                                   "children"=>[varName])
            }
            to buildIbid(tempIndex :Int) :Str {
                throw("TODO Markup ibitd")
            }
            to buildCall(rec :Str, verb :Str, args :List[Element], nargs :Map[Str, Element]) :Str {
                throw("TODO markup call")
            }
            to buildDefine(rValue :Str) :Pair[Element, Int] {
                throw("TODO markup define")
            }
            to buildPromise() :Int {
                throw("TODO markup promise")
            }
            to buildDefrec(resIndex :Int, rValue :Str) :Str {
                throw("TODO markup defrec")
            }
        }
    }

    to recognize(markup :Str, builder) :(def _Root := builder.getRootType()) {

        var pendingTags :List[Tuple[Name, Map[Str, Text], List[Content]]] := []
        def root

        def addChild(c :Content) {
            if (pendingTags.size() == 0) {
                if (c =~ text :Text) {
                    builder.buildLiteral(text)
                } else {
                    bind root := builder.buildRoot(c)
                }
            } else {
                def [[n, a, children]] + rest := pendingTags
                pendingTags := [[n, a, children + [c]]] + rest
            }
        }

        object handler {
            to doctype(decl) { traceln(`TODO: build <!doctype$decl>`) }
            to comment(txt) { traceln(`TODO: build <!--$txt-->`) }
            to startElement(name :Name, attrs: Map[Str, Text]) {
                pendingTags := [[name, attrs, []]] + pendingTags
            }
            to characters(chars :Text) { addChild(chars) }
            to endElement(endTagName :Name) {
                def [[startTagName, attrs, children]] + rest := pendingTags
                if (endTagName != startTagName) {
                    throw(`@@TODO: $endTagName != $startTagName ($pendingTags)`)
                }
                def elt := builder.buildCall(makeElement, "run", [startTagName],
                                             ["attrs"=>attrs, "children"=>children])
                pendingTags := rest
                addChild(elt)
            }
            to error([s :Str, ix :Int]) {
                traceln(`@@got ERROR! ${s.slice(ix - 20, ix)}**${s.slice(ix, ix + 1)}**${s.slice(ix + 1, ix+20)}...`)
            }
        }

        def parser := makeMLReader(handler)
        parser.parse(markup)
        return root
    }
}


object deMLNodeKit as DeepFrozen {
    to makeBuilder() {
        var nextTemp :Int := 0
        var varReused := [].asMap().diverge()

        return object deMarkupBuilder implements DEBuilderOf[Content, Element] {
            method getNodeType() :Near { Content }
            method getRootType() :Near { Element }

            to buildRoot(root :Element) :Element { return root }
            to buildLiteral(text :Text) :Content { return text }
            to buildImport(varName :Str) :Element {
                return makeElement("a", "attrs"=>["href"=>varName, "class"=>"import"],
                                   "children"=>[varName])
            }
            to buildIbid(tempIndex :Int) :Element {
                if (! (tempIndex < nextTemp)) { throw(`assertion failure: $tempIndex < $nextTemp`) }
                varReused[tempIndex] := true
                # traceln(`buildIbid: $tempIndex marked reused.`)
                # Represent ibid as intra-document link.
                return makeElement("a", "attrs"=>["href"=>`#ibid$tempIndex`, "class"=>"ibid"],
                                   "children"=>[`[$tempIndex]`])
            }
            to buildCall(==makeElement, =="run", [tagName :Name],
                         ["attrs"=>attrs :Map[Name, Str] := [].asMap(),
                          "children"=>children :List[Content] := []]) :Element {
                return makeElement(tagName, "attrs"=>attrs, "children"=>children)
            }
            to buildDefine(rValue :Element) :Pair[Element, Int] {
                throw("TODO: buildDefine")

                def tempIndex := nextTemp
                nextTemp += 1
                varReused[tempIndex] := false
                def tempName := ["ibid", tempIndex]
                # hmm... can we make this optimization locally?
                def defElement := if (rValue =~ Literal) { rValue } else { ["define", tempIndex, rValue] }
                return [defElement, tempIndex]
            }
            to buildPromise() :Int {
                throw("TODO: buildPromise")

                def promIndex := nextTemp
                nextTemp += 2
                varReused[promIndex] := false
                varReused[promIndex + 1] := false
                return promIndex
            }
            to buildDefrec(resIndex :Int, rValue :Element) :Element {
                throw("TODO: buildDefrec")

                def promIndex := resIndex - 1
                # traceln(`buildDefrec: $promIndex reused? ${varReused[promIndex]}.`)
                return if (varReused[promIndex]) {
                    # We have a cycle
                    ["defrec", promIndex, rValue]
                } else {
                    # No cycle
                    ["define", promIndex, rValue]
                }
            }
        }
    }

    to recognize() {
        throw("@@not implemented")
        #@@Char
    }
}


def kitTest(assert) as DeepFrozen:
    def parse := fn m { deMarkupKit.recognize(m, deMLNodeKit.makeBuilder()) }
    for [m, rootTag] in ([
        ["<p></p>", "p"],
        ["<br />", "br"],
        ["<h2>AT&amp;T</h2>", "h2"],
        ["<h2>AT & T</h2>", "h2"],
        ["<h2>AT &#65; T</h2>", "h2"],
        ["<p > a < b </p>", "p"],
        ["<!--<h1>--><p>..</p>", "p"],
        ["<!doctype html><html>...</html>", "html"],
        ["<p ></p >", "p"],
        ["<p>sdlkf<em class='xx'>WHEE!</em \n>...</p >", "p"],
        ["<div><a href='x'   class=\"fun\"   >...</a>sdlfkj</div>", "div"],
        ["<div><a href=\"y\">...</a>sdlfkj</div>", "div"],
        ["<<p>hi</p>", "p"],
        ["<my-stuff>...</my-stuff>", "my-stuff"]
    ]):
        # traceln(`markup: $m`)
        def doc := parse(m)
        # traceln(`parsed doc: $doc`)
        def [_rx, _verb, [actual], _nargs] := doc._uncall()
        assert.equal(actual, rootTag)

    assert.equal(parse("<a href='AT&amp;T'>...</a>").getAttr("href"), "AT&T")


unittest([
    oneOfTest,
    nameTests,
    kitTest
])


def main(args :List[Str], =>makeFileResource) :Vow[Int] as DeepFrozen:
    def runTests():
        var successes :Int := 0
        var failures :Int := 0
        object assert:
            to equal(l, r):
                if (l == r) {
                    successes += 1
                } else {
                    traceln(`failed: $l == $r`)
                    failures += 1
                }
            to throws(f):
                try:
                    f()
                    traceln(`did not throw: $f`)
                    failures += 1
                catch _:
                    successes += 1

        oneOfTest(assert)
        nameTests(assert)
        kitTest(assert)
        traceln(["success" => successes, "failure" => failures])
        return 0

    if (args =~ [_eval, _script, fname] + _):
        traceln(`$fname: reading...`)
        return when (def bs := makeFileResource(fname) <- getContents()) ->
            traceln(`$fname: UTF8 decoding ${bs.size()} bytes...`)
            def markup := UTF8.decode(bs, throw)
            traceln(`$fname: parsing ${markup.size()} chars...`)
            def doc := deMarkupKit.recognize(markup, deMLNodeKit.makeBuilder())
            def [_rx, _verb, [root], _nargs] := doc._uncall()
            traceln(`root: $root`)
            0
        catch oops:
            traceln.exception(oops)
            1
    else:
        return runTests()

