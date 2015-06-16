# interface Tag :DeepFrozen guards TagStamp :DeepFrozen:
#     pass
object TagStamp:
    to audit(_):
        return true

object Tag:
    to coerce(specimen, ej):
        return specimen
        #if (__auditedBy(TagStamp, specimen)):
        #    return specimen
        # ej(null)

object makeTag as DeepFrozen:
    to asType():
        return Tag
    to run(code :NullOk[Int], name :Str, dataGuard :DeepFrozen):
        return object tag implements TagStamp:
            to _uncall():
                return [makeTag, "run", [code, name, dataGuard]]

            to _printOn(out):
                out.print("<")
                out.print(name)
                if (code != null):
                    out.print(":")
                    out.print(code)
                if (dataGuard != null):
                    out.print(":")
                    out.print(dataGuard)
                out.print(">")

            to getCode():
                return code

            to getName():
                return name

            to getDataGuard():
                return dataGuard

            to isTagForData(data) :Bool:
                if (data == null):
                    return true
                if (dataGuard == null):
                    return false

                return data =~ _ :dataGuard

            to op__cmp(other):
                return name.op__cmp(other.getName())

def optMakeTagFromData(val, mkt):
    switch (val):
        match ==null:
            return mkt("null", null)
        match ==true:
            return mkt("true", null)
        match ==false:
            return mkt("false", null)
        match v :Int:
            return mkt(".int.", v)
        match v :Double:
            return mkt(".float64.", v)
        match v :Str:
            return mkt(".String.", v)
        match v :Char:
            return mkt(".char.", v)
        match _:
            return null

object TermStamp as DeepFrozen:
    to audit(_):
        return true

def TermData :DeepFrozen := Any#[NullOk, Str, Int, Double, Char]

object Term as DeepFrozen:
    to coerce(specimen, ej):
        if (!__auditedBy(TermStamp, specimen)):
            def coerced := specimen._conformTo(Term)
            if (!__auditedBy(TermStamp, coerced)):
                throw.eject(ej, `not a Term: ${M.toQuote(specimen)}`)
        return specimen


object makeTerm as DeepFrozen:
    to asType():
        return Term

    to run(tag :Tag, data :TermData, args :List, span):
        if (data != null && args != []):
            throw(`Term $tag can't have both data and children`)

        return object term implements TermStamp:
            to _uncall():
                return [makeTerm, "run", [tag, data, args, span]]

            to withSpan(newSpan):
                return makeTerm(tag, data, args, newSpan)

            to getTag():
                return tag

            to getData():
                return data

            to getSpan():
                return span

            to getArgs():
                return args

            to asFunctor():
                return term

            to withoutArgs():
               return makeTerm(tag, data, [], span)

            to op__cmp(other):
               var tagCmp := tag.op__cmp(other.getTag())
               if (tagCmp != 0):
                   return tagCmp
               if (data == null):
                   if (other.getData() != null):
                       return -1
               else:
                   if (other.getData() == null):
                       return 1
                   def dataCmp := data.op__cmp(other.getData())
                   if (dataCmp != 0):
                       return dataCmp
               return args.op__cmp(other.getArgs())

            # Used for pretty printing. Oughta be cached, but we need a
            # primitive memoizer for that to be DeepFrozen.
            to getHeight():
                var myHeight := 1
                if (args != null):
                    for a in args:
                        def h := a.getHeight()
                        if (h + 1 > myHeight):
                            myHeight := h + 1
                return myHeight

            to _conformTo(guard):
                def x := args != null && args.size() == 0
                if (x && [Str, Double, Int, Char].contains(guard)):
                    if (data == null):
                        return tag.getName()
                    return data
                else:
                    return term

            to _printOn(out):
                out.print("term`")
                term.prettyPrintOn(out, false)
                out.print("`")

            to prettyPrintOn(out, isQuasi :Bool):
                var label := null # should be def w/ later bind
                var reps := null
                var delims := null
                switch (data):
                    match ==null:
                        label := tag.getName()
                    match f :Double:
                        if (f.isNaN()):
                            label := "%NaN"
                        else if (f.isInfinite()):
                            if (f > 0):
                                label := "%Infinity"
                            else:
                                label := "-%Infinity"
                        else:
                            label := `$data`
                    match s :Str:
                        label := s.quote().replace("\n", "\\n")
                    match _:
                        label := M.toQuote(data)

                if (isQuasi):
                    # Escape QL characters.
                    label := label.replace("$", "$$").replace("@", "@@")
                    label := label.replace("`", "``")

                if (label == ".tuple."):
                    if (term.getHeight() <= 1):
                        out.print("[]")
                        return
                    reps := 1
                    delims := ["[", ",", "]"]
                else if (label == ".bag."):
                    if (term.getHeight() <= 1):
                        out.print("{}")
                        return
                    reps := 1
                    delims := ["{", ",", "}"]
                else if (args == null):
                    out.print(label)
                    return
                else if (args.size() == 1 && (args[0].getTag().getName() != null)):
                    out.print(label)
                    out.print("(")
                    args[0].prettyPrintOn(out, isQuasi)
                    out.print(")")
                    return
                else if (args.size() == 2 && label == ".attr."):
                    reps := 4
                    delims := ["", ":", ""]
                else:
                    out.print(label)
                    if (term.getHeight() <= 1):
                        # Leaf, so no parens.
                        return
                    reps := label.size() + 1
                    delims := ["(", ",", ")"]
                def [open, sep, close] := delims
                out.print(open)

                if (term.getHeight() == 2):
                    # We only have leaves, so we can probably get away with
                    # printing on a single line.
                    args[0].prettyPrintOn(out, isQuasi)
                    for a in args.slice(1):
                        out.print(sep + " ")
                        a.prettyPrintOn(out, isQuasi)
                    out.print(close)
                else:
                    def sub := out.indent(" " * reps)
                    args[0].prettyPrintOn(sub, isQuasi)
                    for a in args.slice(1):
                        sub.println(sep)
                        a.prettyPrintOn(sub, isQuasi)
                    sub.print(close)

def mkt(name, data) as DeepFrozen:
    return makeTerm(makeTag(null, name, Any), data, [], null)

object termBuilder:
    to leafInternal(tag, data, span):
        return makeTerm(tag, data, [], span)

    to leafData(data, span):
        return optMakeTagFromData(data, mkt)

    to composite(tag, data, span):
        return termBuilder.term(termBuilder.leafInternal(tag, null, span))

    to term(functor, args):
        if (functor.getArgs().size() > 0):
            throw(`To use as a functor, a Term must not have args: $functor`)
        return makeTerm(functor.getTag(), functor.getData(), args.snapshot(), functor.getSpan())

    to empty():
        return [].diverge()

    to addArg(arglist, arg):
        arglist.push(arg)
        return arglist

object VALUE_HOLE {}
object PATTERN_HOLE {}
object EOF {}
def decimalDigits := '0'..'9'
def hexDigits := decimalDigits | 'a'..'f' | 'A'..'F'

# huh, maybe regions are dumb for this? guess we need sets
def segStart := 'a'..'z' | 'A'..'Z' | '_'..'_' | '$'..'$' | '.'..'.'
def segPart := segStart | '0'..'9' | '-'..'-'
def closers := ['(' => ')', '[' => ']', '{' => '}']


def _makeTermLexer(input, builder, braceStack, var nestLevel):

    # The character under the cursor.
    var currentChar := null
    # Offset of the current character.
    var position := -1

    # Start offset of the text for the token being created.
    var startPos := -1

    # Syntax error produced from most recent tokenization attempt.
    var errorMessage := null

    var count := -1

    def leafTag(tagname, span):
        return builder.leafInternal(makeTag(null, tagname, Any), null, span)


    def atEnd():
        return position == input.size()

    def advance():
        position += 1
        if (atEnd()):
            currentChar := EOF
        else:
             currentChar := input[position]
        return currentChar

    def peekChar():
        if (atEnd()):
            throw("attempt to read past end of input")
        if (position + 1 == input.size()):
            return EOF
        return input[position + 1]

    def pushBrace(opener, closer, indent, canNest):
        if (canNest):
            nestLevel += 1
        braceStack.push([opener, closer, indent, canNest])

    def popBrace(closer, fail):
        if (braceStack.size() <= 1):
            fail(`Unmatched closing character ${closer.quote()}`)
        else if (braceStack.last()[1] != closer):
            fail(`Mismatch: ${closer.quote()} doesn't close ${braceStack.last()[0]}`)
        def item := braceStack.pop()
        if (item[3]):
            nestLevel -= 1

    def skipWhitespace():
        if (atEnd()):
            return
        while (['\n', ' '].contains(currentChar)):
            advance()

    def startToken():
        if (startPos >= 0):
            throw("Token already started")
        startPos := position

    def endToken(fail):
        def pos := position
        def tok := input.slice(startPos, pos)
        startPos := -1
        return tok

    def collectDigits(var digitset):
        if (atEnd() || !digitset(currentChar)):
            return false
        digitset |= ('_'..'_')
        while (!atEnd() && digitset(currentChar)):
            advance()
        return true

    def numberLiteral(fail):
        var radix := 10
        var floating := false
        if (currentChar == '0'):
            advance()
            if (currentChar == 'X' || currentChar == 'x'):
                radix := 16
                advance()
        if (radix == 16):
            collectDigits(hexDigits)
        else:
            collectDigits(decimalDigits)
            if (currentChar == '.'):
                def pc := peekChar()
                if (pc == EOF):
                    fail("Missing fractional part")
                if (decimalDigits(pc)):
                    advance()
                    floating := true
                    collectDigits(decimalDigits)
            if (currentChar == 'e' || currentChar == 'E'):
                advance()
                floating := true
                if (currentChar == '-' || currentChar == '+'):
                    advance()
                if (!collectDigits(decimalDigits)):
                    fail("Missing exponent")
        def tok := endToken(fail)
        def s := tok.replace("_", "")
        if (floating):
            return builder.leafInternal(makeTag(null, ".float64.", Any), __makeDouble(s), tok.getSpan())
        else:
            if (radix == 16):
                return builder.leafInternal(makeTag(null, ".int.", Any), __makeInt(s.slice(2), 16), tok.getSpan())
            else:
                return builder.leafInternal(makeTag(null, ".int.", Any), __makeInt(s), tok.getSpan())

    def charConstant(fail):
        if (currentChar == '\\'):
            def nex := advance()
            if (nex == 'u'):
                def hexstr := __makeString.fromChars([advance(), advance(), advance(), advance()])
                def v
                try:
                    bind v := __makeInt(hexstr, 16)
                catch _:
                    throw.eject(fail, "\\u escape must be four hex digits")
                advance()
                return '\x00' + v
            else if (nex == 'x'):
                def v
                try:
                    bind v := __makeInt(__makeString.fromChars([advance(), advance()]), 16)
                catch _:
                    throw.eject(fail, "\\x escape must be two hex digits")
                advance()
                return '\x00' + v
            else if (nex == EOF):
                throw.eject(fail, "End of input in middle of literal")
            def c := [
                'b' => '\b',
                't' => '\t',
                'n' => '\n',
                'f' => '\f',
                'r' => '\r',
                '"' => '"',
                '\'' => '\'',
                '\\' => '\\',
                '\n' => null,
                ].fetch(nex, fn{-1})
            if (c == -1):
                throw.eject(fail, `Unrecognized escape character ${nex.quote()}`)
            else:
                advance()
                return c
        if (currentChar == EOF):
            throw.eject(fail, "End of input in middle of literal")
        else if (currentChar == '\t'):
            throw.eject(fail, "Quoted tabs must be written as \\t")
        else:
            def c := currentChar
            advance()
            return c

    def stringLike(fail):
        def opener := currentChar
        advance()
        pushBrace(opener, '"', 0, false)
        def buf := [].diverge()
        while (currentChar != '"'):
            if (atEnd()):
                fail("Input ends inside string literal")
            def cc := charConstant(fail)
            if (cc != null):
               buf.push(cc)
        advance()
        return __makeString.fromChars(buf.snapshot())

    def charLiteral(fail):
        advance()
        var c := charConstant(fail)
        while (c == null):
           c := charConstant(fail)
        if (currentChar != '\''):
            throw.eject(fail, "Character constant must end in \"'\"")
        advance()
        return builder.leafInternal(makeTag(null, ".char.", Any), c, endToken(fail).getSpan())

    def tag(fail, initial):
        var done := false
        def segs := [].diverge()
        if (initial != null):
            segs.push(initial)
        while (currentChar == ':' && peekChar() == ':'):
            advance()
            advance()
            if (currentChar == '"'):
                def s := stringLike(fail)
                segs.push("::\"")
                segs.push(s)
                segs.push("\"")
            else:
                segs.push("::")
                def segStartPos := position
                if (currentChar != EOF && segStart(currentChar)):
                    advance()
                else:
                    throw.eject(fail, "Invalid character starting tag name segment")
                while (currentChar != EOF && segPart(currentChar)):
                    advance()
                segs.push(input.slice(segStartPos, position))
        return leafTag("".join(segs), endToken(fail).getSpan())

    def getNextToken(fail):
        skipWhitespace()
        startToken()
        def cur := currentChar
        if (cur == EOF):
            throw.eject(fail, null)
        if (cur == '"'):
            def s := stringLike(fail)
            def closer := endToken(fail)
            popBrace('"', fail)

            return builder.leafInternal(makeTag(null, ".String.", Any), s, closer.getSpan())
        if (cur == '\''):
            return charLiteral(fail)
        if (cur == '-'):
            advance()
            return numberLiteral(fail)
        if (decimalDigits(cur)):
            return numberLiteral(fail)
        if (segStart(cur)):
            def segStartPos := position
            advance()
            while (currentChar != EOF && segPart(currentChar)):
                advance()
            return tag(fail, input.slice(segStartPos, position))
        if (cur == ':' && peekChar() == ':'):
            return tag(fail, null)
        if (['(', '[','{'].contains(cur)):
            pushBrace(cur, closers[cur], 1, true)
            def s := input.slice(position, position + 1)
            def t := leafTag(s, s.getSpan())
            advance()
            return t
        if ([')', ']', '}'].contains(cur)):
            popBrace(cur, fail)
            def s := input.slice(position, position + 1)
            def t := leafTag(s, s.getSpan())
            advance()
            return t
        if ([':', '-', ',', '*', '+', '?'].contains(cur)):
            def s := input.slice(position, position + 1)
            def t := leafTag(s, s.getSpan())
            advance()
            return t
        fail(`Unrecognized character ${cur.quote()}`)

    advance()
    return object termLexer:

        to _makeIterator():
            return termLexer

        to getSyntaxError():
            return errorMessage

        to valueHole():
            return VALUE_HOLE

        to patternHole():
            return PATTERN_HOLE

        to next(ej):
            try:
                if (currentChar == EOF):
                    throw.eject(ej, null)
                def errorStartPos := position
                escape e:
                    def t := getNextToken(e)
                    return [count += 1, t]
                catch msg:
                    errorMessage := msg
                    throw.eject(ej, msg)
            finally:
                startPos := -1

        to lexerForNextChunk(chunk):
            return _makeTermLexer(chunk, builder, braceStack, nestLevel)

object makeTermLexer:
    to run(input, builder):
        # State for paired delimiters like "", {}, (), []
        def braceStack := [[null, null, 0, true]].diverge()
        return _makeTermLexer(input, builder, braceStack, 0)

    to holes():
        return [VALUE_HOLE, PATTERN_HOLE]

def convertToTerm(val, ej) as DeepFrozen:
    if (val =~ _ :Term):
        return val
    if ((def t := optMakeTagFromData(val, mkt)) != null):
        return t
    switch (val):
        match v :List:
            def ts := [].diverge()
            for item in v:
               ts.push(convertToTerm(item, ej))
            def l := ts.snapshot()
            return makeTerm(makeTag(null, ".tuple.", Any), null, l, null)
        # match v :set:
        #   return mkt(".bag.", null, [for item in (v) convertToTerm(item)])
        match m :Map:
            def mm := [].diverge()
            for k => v in m:
                mm.push(makeTerm(makeTag(null, ".attr.", Any), null, [convertToTerm(k, ej),
                       convertToTerm(v, ej)], null))
            return makeTerm(makeTag(null, ".bag.", Any), null,
                       mm.snapshot(), null)
        match _:
            throw.eject(ej, `Could not coerce $val to term`)

object qEmptySeq:
    to reserve():
        return 0

    to startShape(values, bindings, prefix, shapeSoFar):
        return shapeSoFar

    to endShape(bindings, prefix, shape):
        null

    to substSlice(values, indices):
        return []

    to matchBindSlice(args, specimens, bindings, indices, max):
        return 0


def makeQPairSeq(left, right):
    return object qpair:
        to getLeft():
            return left

        to getRight():
            return right

        to getSpan():
            return null

        to startShape(values, bindings, prefix, var shapeSoFar):
            shapeSoFar := left.startShape(values, bindings, prefix, shapeSoFar)
            return right.startShape(values, bindings, prefix, shapeSoFar)

        to endShape(bindings, prefix, shape):
            left.endShape(bindings, prefix, shape)
            right.endShape(bindings, prefix, shape)

        to substSlice(values, indices):
            def v := left.substSlice(values, indices) + right.substSlice(values, indices)
            return v

        to matchBindSlice(args, specimens, bindings, indices, max):
            def leftNum := left.matchBindSlice(args, specimens, bindings, indices,
                                               max - right.reserve())
            if (leftNum < 0):
                return -1
            def rightNum := right.matchBindSlice(args, specimens.slice(leftNum),
                                                 bindings, indices, max - leftNum)
            if (rightNum < 0):
                return -1
            return leftNum + rightNum

        to reserve():
            return left.reserve() + right.reserve()


def matchCoerce(val, isFunctorHole, tag):
    var result := null
    if (isFunctorHole):
        def mkt(name, data, args):
            return makeTerm(makeTag(null, name, Any), data, args, null)
        switch (val):
            match _ :Term:
                if (val.getArgs().size() != 0):
                    return null
                result := val
            match ==null:
                result := mkt("null", null, [])
            match ==true:
                result := mkt("true", null, [])
            match ==false:
                result := mkt("false", null, [])
            match v :Str:
                result := mkt(v, null, [])
            match _:
                return null
    else:
        escape e:
            result := convertToTerm(val, e)
        catch _:
            return null
    if (tag == null || tag <=> result.getTag()):
        return result
    return null


def makeQTerm(functor, args):
    def coerce(termoid):
        if (termoid !~ _ :Term):
            return matchCoerce(termoid, functor.getIsFunctorHole(), functor.getTag())
        def newFunctor := matchCoerce(termoid.withoutArgs(), functor.getIsFunctorHole(), functor.getTag())
        if (newFunctor == null):
            return null
        return makeTerm(newFunctor.getTag(), newFunctor.getData(), termoid.getArgs(), termoid.getSpan())

    return object qterm:
        to isHole():
            return false

        to getFunctor():
            return functor

        to getArgs():
            return args

        to startShape(values, bindings, prefix, var shapeSoFar):
            shapeSoFar := functor.startShape(values, bindings, prefix, shapeSoFar)
            shapeSoFar := args.startShape(values, bindings, prefix, shapeSoFar)
            return shapeSoFar

        to endShape(bindings, prefix, shape):
            functor.endShape(bindings, prefix, shape)
            functor.endShape(bindings, prefix, shape)

        to substSlice(values, indices):
            def tFunctor := functor.substSlice(values, indices)[0]
            def tArgs := args.substSlice(values, indices)
            def term := makeTerm(tFunctor.getTag(), tFunctor.getData(),
                                 tArgs, tFunctor.getSpan())
            return [term]

        to matchBindSlice(values, specimens, bindings, indices, max):
            if (specimens.size() <= 0):
                return -1
            def specimen := coerce(specimens[0])
            if (specimen == null):
                return -1
            def matches := functor.matchBindSlice(values, [specimen.withoutArgs()],
                                                  bindings, indices, 1)
            if (matches <= 0):
                return -1
            if (matches != 1):
                throw("Functor may only match 0 or 1 specimen: ", matches)
            def tArgs := specimen.getArgs()
            def num := args.matchBindSlice(values, tArgs,
                                           bindings, indices, tArgs.size())
            if (tArgs.size() == num):
                if (max >= 1):
                  return 1
            return -1

        to reserve():
            return 1

def makeQFunctor(tag, data, span):
    return object qfunctor:
        to _printOn(out):
            out.print(tag.getName())

        to isHole():
            return false

        to getIsFunctorHole():
            return false

        to getTag():
            return tag

        to getData():
            return data

        to getSpan():
            return span

        to asFunctor():
            return qfunctor

        to reserve():
            return 1

        to startShape(args, bindings, prefix, shapeSoFar):
            return shapeSoFar

        to endShape(bindings, prefix, shape):
            null

        to substSlice(values, indices):
            if (data == null):
                return [termBuilder.leafInternal(tag, null, span)]
            else:
                return [termBuilder.leafData(data, span)]

        to matchBindSlice(args, specimens, bindings, indices, max):
            if (specimens.size() <= 0):
                 return -1
            def spec := matchCoerce(specimens[0], true, tag)
            if (spec == null):
                return -1
            if (data != null):
                def otherData := spec.getData()
                if (otherData == null):
                    return -1
                if (data != otherData):
                    if ([data, otherData] =~ [_ :Str, _ :Str]):
                        if (data.bare() != otherData.bare()):
                            return -1
            if (max >= 1):
                return 1
            return -1


def multiget(args, num, indices, repeat):
    var result := args[num]
    for i in indices:
         if (result =~ rlist :List):
            result := rlist[i]
         else:
            if (repeat):
                return result
            throw("index out of bounds")
    return result


def multiput(bindings, holeNum, indices, newVal):
    var list := bindings
    var dest := holeNum
    for i in indices:
        if (list.size() < dest + 1):
            throw("Index out of bounds")
        var next := list[dest]
        if (next == null):
            next := [].diverge()
            list[dest] := next
        list := next
        dest := i
    var result := null
    if (list.size() > dest):
        result := list[dest]
        list[dest] := newVal
    else if (list.size() == dest):
        list.push(newVal)
    else:
        throw("what's going on in here")
    return result


def makeQDollarHole(tag, holeNum, isFunctorHole):
    return object qdollarhole:

        to isHole():
            return true

        to getTag():
            return tag

        to getHoleNum():
            return holeNum

        to getSpan():
            return null

        to getIsFunctorHole():
            return isFunctorHole

        to asFunctor():
            if (isFunctorHole):
                return qdollarhole
            else:
                return makeQDollarHole(tag, holeNum, true)

        to startShape(values, bindings, prefix, shapeSoFar):
            def t := multiget(values, holeNum, prefix, true)
            if (t =~ vals :List):
                def result := vals.size()
                if (![-1, result].contains(shapeSoFar)):
                    throw(`Inconsistent shape: $shapeSoFar vs $result`)
                return result
            return shapeSoFar

        to endShape(bindings, prefix, shape):
            null

        to substSlice(values, indices):
            def termoid := multiget(values, holeNum, indices, true)
            def term := matchCoerce(termoid, isFunctorHole, tag)
            if (term == null):
                throw(`Term $termoid doesn't match $qdollarhole`)
            return [term]

        to matchBindSlice(args, specimens, bindings, indices, max):
            if (specimens.size() <= 0):
                return -1
            def specimen := specimens[0]
            def termoid := multiget(args, holeNum, indices, true)
            def term := matchCoerce(termoid, isFunctorHole, tag)
            if (term == null):
                throw(`Term $termoid doesn't match $qdollarhole`)
            if (term <=> specimen):
                if (max >= 1):
                    return 1
            return -1

        to reserve():
            return 1


def makeQAtHole(tag, holeNum, isFunctorHole):
    return object qathole:
        to isHole():
            return true

        to getTag():
            return tag

        to getSpan():
            return null

        to getHoleNum():
            return holeNum

        to getIsFunctorHole():
            return isFunctorHole

        to asFunctor():
            if (isFunctorHole):
                return qathole
            else:
                return makeQAtHole(tag, holeNum, true)

        to startShape(values, bindings, prefix, shapeSoFar):
            # if (bindings == null):
            #     throw("no at-holes in a value maker")
            multiput(bindings, holeNum, prefix, [].diverge())
            return shapeSoFar

        to endShape(bindings, prefix, shape):
            def bits := multiget(bindings, holeNum, prefix, false)
            multiput(bindings, holeNum, prefix, bits.slice(0, shape))

        to substSlice(values, indices):
            throw("A quasiterm with an @-hole may not be used in a value context")

        to matchBindSlice(args, specimens, bindings, indices, max):
            if (specimens.size() <= 0):
                return -1
            def spec := matchCoerce(specimens[0], isFunctorHole, tag)
            if (spec == null):
                return -1
            def oldVal := multiput(bindings, holeNum, indices, spec)
            if (oldVal == null || oldVal <=> spec):
                if (max >= 1):
                    return 1

            return -1

        to reserve():
            return 1

def inBounds(num, quant):
    switch (quant):
        match =="?":
            return num == 0 || num == 1
        match =="+":
            return num >= 1
        match =="*":
            return num >= 0
    return false

def makeQSome(subPattern, quant, span):
    return object qsome:
        to getSubPattern():
            return subPattern

        to getQuant():
            return quant

        to getSpan():
            return span
        to reserve():
            switch (quant):
                match =="?":
                    return 0
                match =="+":
                    return subPattern.reserve()
                match =="*":
                    return 0

        to startShape(values, bindings, prefix, shapeSoFar):
            return subPattern.startShape(values, bindings, prefix, shapeSoFar)

        to endShape(bindings, prefix, shape):
            return subPattern.endShape(bindings, prefix, shape)

        to substSlice(values, indices):
            def shape := subPattern.startShape(values, [], indices, -1)
            if (shape < 0):
                throw(`Indeterminate repetition: $qsome`)
            def result := [].diverge()
            for i in 0..!shape:
                result.extend(subPattern.substSlice(values, indices + [i]))
            subPattern.endShape([], indices, shape)
            if (!inBounds(result.size(), quant)):
                throw(`Improper quantity: $shape vs $quant`)
            return result.snapshot()

        to matchBindSlice(values, var specimens, bindings, indices, var max):
            def maxShape := subPattern.startShape(values, bindings, indices, -1)
            var result := 0
            var shapeSoFar := 0
            while (maxShape == -1 || shapeSoFar < maxShape):
                if (specimens.size() == 0):
                    break
                if (quant == "?" && result > 0):
                    break
                def more := subPattern.matchBindSlice(values, specimens, bindings,
                                                      indices + [shapeSoFar], max)
                if (more == -1):
                    break
                max -= more
                if (more < 0 && maxShape == -1):
                    throw(`Patterns of indeterminate rank must make progress: $qsome vs $specimens`)
                result += more
                specimens := specimens.slice(more)
                shapeSoFar += 1
            subPattern.endShape(bindings, indices, shapeSoFar)
            if (!inBounds(result, quant)):
                throw("Improper quantity: $result vs $quant")
            return result

def tokenStart := 'a'..'z' | 'A'..'Z' | '_'..'_' | '$'..'$' | '.'..'.'


def mkq(name, data):
    return makeQFunctor(makeTag(null, name, Any), data, null)

object qBuilder:
    to leafInternal(tag, data, span):
        return makeQFunctor(tag, data, span)

    to leafData(data, span):
        return makeQFunctor(optMakeTagFromData(data, mkq), data, span)

    to composite(tag, data, span):
        return qBuilder.term(qBuilder.leafInternal(tag, null, span), qBuilder.leafData(data, span))

    to term(functor, args):
        if (functor.isHole() && !functor.getIsFunctorHole()):
            return functor
        return makeQTerm(functor, args)

    to some(sub, quant):
        return makeQSome(sub, quant, if (sub == null) {null} else {sub.getSpan()})

    to empty():
        return qEmptySeq

    to addArg(arglist, arg):
        return makeQPairSeq(arglist, arg)


def _parseTerm(lex, builder, err):
    def [VALUE_HOLE, PATTERN_HOLE] := [lex.valueHole(), lex.patternHole()]
    def tokens := __makeList.fromIterable(lex)
    var dollarHoleValueIndex := -1
    var atHoleValueIndex := -1
    var position := -1

    def onError(e, msg):
        def syntaxError(_):
            e(msg)
        return syntaxError

    def advance(ej):
        position += 1
        if (position >= tokens.size()):
            ej("hit EOF")
        return tokens[position]

    def rewind():
        position -= 1

    def peek():
        if (position + 1 >= tokens.size()):
            return null
        return tokens[position + 1]

    def accept(termName, fail):
        def t := advance(fail)
        def isHole := t == VALUE_HOLE || t == PATTERN_HOLE
        if (!isHole && t.getTag().getName() == termName):
            return t
        else:
            rewind()
            fail(`expected $termName, got $t`)

    def maybeAccept(termName):
        escape e:
            def t := advance(e)
            def isHole := t == VALUE_HOLE || t == PATTERN_HOLE
            if (!isHole && t.getTag().getName() == termName):
                return t
        rewind()
        return null

    def functor(fail):
        def token := advance(fail)
        if (token == VALUE_HOLE):
            return makeQDollarHole(null, dollarHoleValueIndex += 1, false)
        if (token == PATTERN_HOLE):
            return makeQAtHole(null, atHoleValueIndex += 1, false)
        if (token.getData() != null):
            return token
        def name := token.getTag().getName()
        if (name.size() > 0 && tokenStart(name[0])):
            if (peek() == VALUE_HOLE):
                advance(fail)
                return makeQDollarHole(token, dollarHoleValueIndex += 1, false)
            if (peek() == PATTERN_HOLE):
                advance(fail)
                return makeQAtHole(token.getTag(), atHoleValueIndex += 1, false)
            return token
        rewind()
        fail(null)

    def term
    def arglist(closer, fail):
        var args := builder.empty()
        escape e:
            args := builder.addArg(args, term(e))
        catch err:
            accept(closer, fail)
            return args
        escape outOfArgs:
            while (true):
                accept(",", outOfArgs)
                args := builder.addArg(args, term(outOfArgs))
        accept(closer, fail)
        return args
    def namedTerm(name, args):
        return builder.term(builder.leafInternal(makeTag(null, name, Any), null, null), args)
    def extraTerm(fail):
        if (maybeAccept("[") != null):
            return namedTerm(".tuple.", arglist("]", fail))
        else if (maybeAccept("{") != null):
            return namedTerm(".bag.", arglist("}", fail))
        def rootTerm := functor(fail)
        if (maybeAccept("{") != null):
            def f := rootTerm.asFunctor()
            return builder.term(f, builder.addArg(builder.empty(), namedTerm(".bag.", arglist("}", fail))))
        if (maybeAccept("(") != null):
            def f := rootTerm.asFunctor()
            return builder.term(f, arglist(")", fail))
        return builder.term(rootTerm, builder.empty())

    def prim(fail):
        def k := extraTerm(fail)
        if (maybeAccept(":") != null):
            def v := extraTerm(onError(fail, "Expected term after ':'"))
            return namedTerm(".attr.", builder.addArg(builder.addArg(builder.empty(), k), v))
        else:
            return k

    def some(t):
        if (maybeAccept("*") != null):
            return builder.some(t, "*")
        if (maybeAccept("+") != null):
            return builder.some(t, "+")
        if (maybeAccept("?") != null):
            return builder.some(t, "?")
        return t

    bind term(fail):
        if (maybeAccept("(") != null):
            return some(arglist(")", fail))
        return some(prim(fail))

    term # deleting this line breaks tests. is there some compiler BS going on?
    return prim(err)

def parseTerm(input):
    def lex := makeTermLexer(input, termBuilder)
    return _parseTerm(lex, termBuilder, throw)

def makeQuasiTokenChain(makeLexer, template):
    var i := -1
    var current := makeLexer("", qBuilder)
    var lex := current
    def [VALUE_HOLE, PATTERN_HOLE] := makeLexer.holes()
    var j := 0
    return object chainer:
        to _makeIterator():
            return chainer

        to valueHole():
           return VALUE_HOLE

        to patternHole():
           return PATTERN_HOLE

        to next(ej):
            if (i >= template.size()):
                throw.eject(ej, null)
            j += 1
            if (current == null):
                if (template[i] == VALUE_HOLE || template[i] == PATTERN_HOLE):
                    def hol := template[i]
                    i += 1
                    return [j, hol]
                else:
                    current := lex.lexerForNextChunk(template[i])._makeIterator()
                    lex := current
            escape e:
                def t := current.next(e)[1]
                return [j, t]
            catch z:
                i += 1
                current := null
                return chainer.next(ej)


def [VALUE_HOLE, PATTERN_HOLE] := makeTermLexer.holes()

object quasitermParser:
    to valueHole(n):
        return VALUE_HOLE
    to patternHole(n):
        return PATTERN_HOLE

    to valueMaker(template):
        def chain := makeQuasiTokenChain(makeTermLexer, template)
        def q := _parseTerm(chain, qBuilder, throw)
        return object qterm extends q:
           to substitute(values):
               def vals := q.substSlice(values, [].diverge())
               if (vals.size() != 1):
                  throw(`Must be a single match: ${vals}`)
               return vals[0]

    to matchMaker(template):
        def chain := makeQuasiTokenChain(makeTermLexer, template)
        def q := _parseTerm(chain, qBuilder, throw)
        return object qterm extends q:
            to matchBind(values, specimen, ej):
                def bindings := [].diverge()
                def blee := q.matchBindSlice(values, [specimen], bindings, [], 1)
                if (blee == 1):
                    return bindings
                else:
                    ej(`$q doesn't match $specimen: $blee`)

    to makeTag(code, name, guard):
        return makeTag(code, name, guard)

    to makeTerm(tag, data, arglist, span):
        return makeTerm(tag, data, arglist, span)


[ "term__quasiParser" => quasitermParser]
