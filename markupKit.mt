# TODO: import "unittest" =~ [=> unittest]
import "guards" =~ [=>Tuple :DeepFrozen]
import "./elib/serial/DEBuilderOf" =~ [=> DEBuilderOf :DeepFrozen]
exports (main, Name, nameStart, nameChar, Element, Text, deMarkupKit)

def nameStart :DeepFrozen := 'a' .. 'z' | 'A' .. 'Z'
def nameChar :DeepFrozen := nameStart | '0' .. '9' | ':' .. ':'


def oneOf(chars :DeepFrozen) as DeepFrozen:
    return object oneOf as DeepFrozen:
        to coerce(specimen, ej):
            if (!chars.contains(specimen)):
                ej(`found $specimen when expecting $chars`)
            return specimen

        to split(s :Str, "max"=>max :NullOk[Int>0] := null) :List[Str]:
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
                    
        to add(rest :DeepFrozen):
            return def concat.coerce(specimen, ej) as DeepFrozen:
                Str.coerce(specimen, ej)
                oneOf.coerce(specimen[0], ej)
                rest.coerce(specimen.slice(1), ej)
                return specimen

        to repeat():
            return def repeat.coerce(specimen, ej) as DeepFrozen:
                for ch in (specimen):
                    oneOf.coerce(ch, ej)
                return specimen

def Name :DeepFrozen := oneOf(nameStart) + oneOf(nameChar).repeat()

# hmm... some characters not allowed, right?
def Text :DeepFrozen := Str

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
    #  implements makerAuditor
    return object element implements Selfless, Element:
        to _uncall():
            # return serializer(makeElement, tag, "attrs"=>attrs, "children"=>children)
            return makeElement(tag, "attrs"=>attrs, "children"=>children)
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

    to recognize(var markup :Str, builder) :(def _Root := builder.getRootType()) {
        def entities := ["amp"=>"&", "lt"=>"<", "gt"=>">", "quot"=>"\"", "apos"=>"'"]  # TODO: parameterize
        def digits := '0' .. '9'
        def Numeral := oneOf(digits).repeat()

        def findDelim(markup) :Tuple[Str, NullOk[Char], Str] {
            def ampFound := markup =~ `@ampPre&@ampPost`
            def ltFound := markup =~ `@ltPre<@ltPost`
            return switch ([ampFound, ltFound]) {
                match ==[true, true] {
                    if (ampPre.size() < ltPre.size()) {
                        [ampPre, '&', ampPost]
                    } else {
                        [ltPre, '<', ltPost]
                    }
                }
                match [==true, _] { [ampPre, '&', ampPost] }
                match [_, ==true] { [ltPre, '<', ltPost] }
                match [_, _] { [markup, null, ""] }
            }
        }

        var pendingTags :List[Tuple[Name, Map[Str, Text], List[Content]]] := []
        def root
        def pushStart(name :Name, attrs: Map[Str, Text]) {
            pendingTags := [[name, attrs, []]] + pendingTags
        }
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
        def popEnd(endTagName :Name) {
            def [[startTagName, attrs, children]] + rest := pendingTags
            if (endTagName != startTagName) {
                throw("@@TODO: handle tag mismatches?!")
            }
            def elt := builder.buildCall(makeElement, "run", [startTagName],
                                         ["attrs"=>attrs, "children"=>children])
            pendingTags := rest
            addChild(elt)
        }

        def doEntity(ampPost :Text) :Text {
            return if (ampPost =~ `#@{charCode :Numeral};@rest`) {
                addChild(('\x00' + _makeInt(charCode)).asString())
                rest
            } else if (ampPost =~ `@{entityName :Name ? (entities.contains(entityName))};@rest`) {
                addChild(entities[entityName])
                rest
            } else {
                addChild("&")
                ampPost
            }
        }

        def ws := [' ', '\n']
        def err(ltPost, ix) {
            traceln(`err: $ix [${ltPost.slice(0, ix)}]`)
            builder.buildCall("@@ERROR", "run", [ltPost.slice(0, ix)], [].asMap())
            markup := ltPost.slice(ix)
        }
        def doStartTag(ltPost :Text) :Text {
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

            escape badTag {
                def tagName := name(badTag)
                def attrs := [].diverge()
                while (nameStart.contains(ch)) {
                    attrs.push(attribute(badTag))
                }
                expect(badTag, ['>'])
                # traceln(`got tag: $tagName $attrs`)
                pushStart(tagName, _makeMap.fromPairs(attrs))
            } catch errIx {
                err(ltPost, errIx)
            }
    
            return ltPost.slice(ix - 1)
        }
        def doEndTag(ltPost: Text) :Text {
            var state := '/'

            for ix => ch in (ltPost) {
                switch (state) {
                    match =='/' { state := 'A' }
                    match =='A' {
                        if(!nameChar.contains(ch)) {
                            popEnd(ltPost.slice(1, ix))
                            if (ch == '>') {
                                return ltPost.slice(ix + 1)
                            }
                            state := '>'
                        }
                    }
                    match =='>' {
                        if (ch == '>') {
                            return ltPost.slice(ix + 1)
                        } else if (ws.contains(ch)) {
                            # keep going...
                        } else {
                            # oops! </name ???
                            # TODO: check html5 spec?
                            err(ltPost, ix)
                            break
                        }
                    }
                }
            }
            return ""
        }

        while(true) {
            def [text, delim, rest] := findDelim(markup)
            if (text.size() > 0) {
                addChild(text)
            }

            # traceln(`M:${markup.slice(0, 4)}... => ${[text, delim, rest]} tags: $pendingTags`)
            switch (delim) {
                match ==null {
                    return root
                }
                match =='&' { markup := doEntity(rest) }
                match =='<' {
                    if (rest == "") {
                        addChild("<")
                        return
                    } else if (rest[0] == '/') {
                        markup := doEndTag(rest)
                    } else if (nameStart.contains(rest[0])) {
                        markup := doStartTag(rest)
                    } else {
                        addChild("<")
                        markup := rest
                    }
                }
                match _ {
                    throw("oops!")
                }
            }
        }
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


def main(_args) :Int as DeepFrozen:
    def unittest(cases):
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
        for case in (cases):
            case(assert)
        
        return ["success"=>successes, "fail"=>failures]
            
    def results := unittest(
        [for [s, d, n, r] in ([
            ["", [], null, [""]],
            ["a   b c", [' '], null, ["a", "b", "c"]],
            ["a \n  b c", [' ', '\n'], null, ["a", "b", "c"]],
            ["a   b c", [' '], 1, ["a", "b c"]]
        ])
         fn assert { assert.equal(oneOf(d).split(s, "max"=>n), r) }] +
        [for n in ([
            "p",
            "h1"
        ]) fn assert { assert.equal(n :Name, n) }] +
        [for s in ([
            "x y",
            "",
            "23"
        ]) fn assert { assert.throws(fn { s :Name }) }]
    )
    traceln(results)

    for m in ([
        "<p></p>",
        "<h2>AT&amp;T</h2>",
        "<h2>AT & T</h2>",
        "<h2>AT &#65; T</h2>",
        "<p > a < b </p>",
        "<p ></p >",
        "<p>sdlkf<em class='xx'>WHEE!</em \n>...</p >",
        "<div><a href='x'   class=\"fun\"   >...</a>sdlfkj</div>",
        "<div><a href=\"y\">...</a>sdlfkj</div>",
        "<<p>hi</p>"]):
        traceln(`markup: $m`)
        def doc := deMarkupKit.recognize(m, deMLNodeKit.makeBuilder())
        traceln(`parsed doc: $doc`)

    return 0
