import "unittest" =~ [=> unittest]
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

def nameStart :DeepFrozen := 'a' .. 'z' | 'A' .. 'Z'
def nameChar :DeepFrozen := nameStart | '0' .. '9' | ':' .. ':'


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
                 =>entities := ["amp"=>"&", "lt"=>"<", "gt"=>">", "quot"=>"\"", "apos"=>"'"]) as DeepFrozen {
    def Numeral := oneOf('0'..'9').plus()

    def doEntity(ampPost :Text) :Text {
        return if (ampPost =~ `#@{charCode :Numeral};@rest`) {
            def ch := ('\x00' + _makeInt(charCode)).asString()
            handler.characters(ch)
            rest
        } else if (ampPost =~ `@{entityName :Name ? (entities.contains(entityName))};@rest`) {
            handler.characters(entities[entityName])
            rest
        } else {
            handler.characters("&")
            ampPost
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
            def mark := ix - 1
            while (ch != delim && advance()) {
                if (['<', '&'].contains(ch)) {
                    throw("#@@TODO: handle &quot; etc. in value")
                }
            }
            def value := ltPost.slice(mark, ix - 1)
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
                    expect(badTag, ['>'])
                    # traceln(`got tag to $ix: $tagName $attrs`)
                    handler.startElement(tagName, _makeMap.fromPairs(attrs))
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
                match =='&' { markup := doEntity(rest) }
                match =='<' {
                    markup := if (rest == "") {
                        handler.characters("<")
                        ""
                    } else if (rest[0] == '/') {
                        makeTag(rest).end()
                    } else if (nameStart.contains(rest[0])) {
                        makeTag(rest).start()
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
                "children"=>children :List[Content] := []) as DeepFrozen:
    return object element implements Selfless, Element:
        to _uncall():
            # return serializer(makeElement, tag, "attrs"=>attrs, "children"=>children)
            return [makeElement, "run", [tag], ["attrs"=>attrs, "children"=>children]]
        to _printOn(p):
            p.print(`<$tag`)
            for n => v in (attrs):
                p.print(` $n="$v"`)   #@@ TODO: fix markup in v
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
            to characters(chars :Text) { addChild(chars) }
            to startElement(name :Name, attrs: Map[Str, Text]) {
                pendingTags := [[name, attrs, []]] + pendingTags
            }
            to endElement(endTagName :Name) {
                def [[startTagName, attrs, children]] + rest := pendingTags
                if (endTagName != startTagName) {
                    throw("@@TODO: handle tag mismatches?!")
                }
                def elt := builder.buildCall(makeElement, "run", [startTagName],
                                             ["attrs"=>attrs, "children"=>children])
                pendingTags := rest
                addChild(elt)
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
    for [m, rootTag] in ([
        ["<p></p>", "p"],
        ["<h2>AT&amp;T</h2>", "h2"],
        ["<h2>AT & T</h2>", "h2"],
        ["<h2>AT &#65; T</h2>", "h2"],
        ["<p > a < b </p>", "p"],
        ["<p ></p >", "p"],
        ["<p>sdlkf<em class='xx'>WHEE!</em \n>...</p >", "p"],
        ["<div><a href='x'   class=\"fun\"   >...</a>sdlfkj</div>", "div"],
        ["<div><a href=\"y\">...</a>sdlfkj</div>", "div"],
        ["<<p>hi</p>", "p"]
    ]):
        # traceln(`markup: $m`)
        def doc := deMarkupKit.recognize(m, deMLNodeKit.makeBuilder())
        # traceln(`parsed doc: $doc`)
        def [_rx, _verb, [actual], _nargs] := doc._uncall()
        assert.equal(actual, rootTag)

unittest([
    oneOfTest,
    nameTests,
    kitTest
])


def main(_args) :Int as DeepFrozen:
    "interactive unit testing: monte eval markupKit.mt
    "
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
