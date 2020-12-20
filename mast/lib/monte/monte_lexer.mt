exports (makeMonteLexer)

def regionToSet(r):
    return [for i in (r) i].asSet()

object VALUE_HOLE as DeepFrozen {}
object PATTERN_HOLE as DeepFrozen {}
object EOF as DeepFrozen {}
def decimalDigits :DeepFrozen := regionToSet('0'..'9')
def hexDigits :DeepFrozen := decimalDigits | regionToSet('a'..'f' | 'A'..'F')

def idStart :DeepFrozen := regionToSet('a'..'z' | 'A'..'Z' | '_'..'_')
def idPart :DeepFrozen := idStart | decimalDigits

def isIdentifierPart(c) as DeepFrozen:
    if (c == EOF):
        return false
    return idPart.contains(c)

def RESERVED_WORDS :DeepFrozen := ["let"].asSet()
def MONTE_KEYWORDS :DeepFrozen := RESERVED_WORDS | [
    "as", "bind", "break", "catch", "continue", "def", "else", "escape",
    "exit", "extends", "exports", "finally", "fn", "for", "guards", "if",
    "implements", "import", "in", "interface", "match", "meta", "method",
    "object", "parameter", "pass", "pragma", "return", "switch", "to", "try",
    "var", "via", "when", "while",
].asSet()

def composite(name, data, span) as DeepFrozen:
    return [[name, data], span]

# `input` is a list of characters and holes. It might not be a string.
def _makeMonteLexer(input, braceStack, var nestLevel, inputName) as DeepFrozen:
    # The character under the cursor.
    var currentChar := null
    # Offset of the current character.
    var position := -1
    # Start offset of the text for the token being created.
    var startPos := -1

    var count := -1

    var lineNumber := 1
    var colNumber := 0
    var tokenStartLine := 1
    var tokenStartCol := 0
    var atLineStart := true
    # Syntax error produced from most recent tokenization attempt.
    var errorMessage := null

    var canStartIndentedBlock := false
    def queuedTokens := [].diverge()
    def indentPositionStack := [0].diverge()

    def quote(token) :Str:
        return switch (token):
            match c :Char:
                c.quote()
            match [==VALUE_HOLE, i, _]:
                `$${${i}}`
            match [==PATTERN_HOLE, i, _]:
                `@@{${i}}`

    def &allLines := makeLazySlot(fn {
        if (input =~ s :Str) {
            # Easy case: If the input is a string, we can use .split/1.
            s.split("\n")
        } else {
            # Hard case: We don't have .split/1 yet, but we do have
            # .startOf/2 and a loop.
            def l := [].diverge()
            var start := 0
            while ((def newline := input.startOf(['\n'], start)) != -1) {
                l.push(input.slice(start, newline))
                start := newline + 1
            }
            l.snapshot()
        }
    })

    def makeParseError(error):
        object parseError:
            to formatCompact():
                if (error =~ [errMsg, span]):
                    if (span == null):
                        return `${allLines.size()}.${allLines.last().size() - 1}: $errMsg`
                    def [sl, el, sc, ec] := [span.getStartLine(), span.getEndLine(),
                                             span.getStartCol() + 1, span.getEndCol() + 1]
                    if (sl == el && sc == ec):
                        return `$sl.$sc: $errMsg`
                    return `$sl.$sc-$el.$ec: $errMsg`

            to formatPretty():
                if (error =~ [errMsg, span]):
                    if (span == null):
                        # There's no span information. This is legal and caused
                        # by token exhaustion.
                        return "Error at end of input: " + errMsg

                    def front := (span.getStartLine() - 3).max(0)
                    def back := span.getEndLine() + 3
                    def lines := allLines.slice(front,
                                                back.min(allLines.size()))
                    def msg := [].diverge()
                    var i := front
                    for line in (lines):
                        i += 1
                        def lnum := M.toString(i)
                        def pad := " " * (4 - lnum.size())
                        msg.push(`$pad$lnum $line`)
                        if (i == span.getStartLine()):
                            def errLine := ("     " + " " *
                                            span.getStartCol() + "^")
                            if (span.getStartLine() == span.getEndLine()):
                                msg.push(errLine + "~" * (span.getEndCol() -
                                                          span.getStartCol() -
                                                          1))
                            else:
                                msg.push(errLine)
                    msg.push(errMsg)
                    def msglines := msg.snapshot()
                    def fullMsg := "\n".join(msglines) + "\n"
                    return fullMsg
                else:
                    return `Unrecognized parser error data $error`

            to _printOn(out):
                out.print(parseError.formatPretty())
        errorMessage := parseError
        return parseError

    def atEnd():
        return position == input.size()

    def spanAtPoint():
        #XXX use twine
        return _makeSourceSpan(inputName, true, lineNumber, colNumber,
                               lineNumber, colNumber + 1)

    def advance():
        position += 1
        if (atLineStart):
            colNumber := 0
            atLineStart := false
        else:
            colNumber += 1
        if (atEnd()):
            currentChar := EOF
        else:
             currentChar := input[position]
        if (currentChar == '\n'):
            lineNumber += 1
            atLineStart := true
        return currentChar

    def peekChar():
        if (atEnd()):
            throw("attempt to read past end of input")
        if (position + 1 == input.size()):
            return EOF
        return input[position + 1]

    def pushBrace(opener, openerSpan, closer, indent, canNest):
        if (canNest):
            nestLevel += 1
        braceStack.push([opener, openerSpan, closer, indent, canNest])

    def popBrace(closer :Any[Str, Char], fail):
        if (braceStack.size() <= 1):
            throw.eject(fail, [`Unmatched closing character ${closer.quote()}`, spanAtPoint()])
        else if (braceStack.last()[2] != closer):
            throw.eject(fail, [`Mismatch: ${closer.quote()} doesn't close ${braceStack.last()[0]}`, spanAtPoint()])
        def item := braceStack.pop()
        if (item[4]):
            nestLevel -= 1

    def inStatementPosition():
        return ["INDENT", null].contains(braceStack.last()[0])

    def skipSpaces():
        if (atEnd()):
            return 0
        def oldPos := position
        while (currentChar == ' '):
            advance()
        return position - oldPos

    def atLogicalEndOfLine():
        if (atEnd()):
            return true
        var i := position
        while ((i < input.size()) && input[i] == ' '):
            i += 1
        def endish := i == input.size() || ['\n', '#'].contains(input[i])
        return endish

    def offsetInLine():
        var i := 0
        while (i < position && input[position - i] != '\n'):
            i += 1
        return i

    def startToken():
        if (startPos >= 0):
            throw("Token already started")
        startPos := position
        tokenStartLine := lineNumber
        tokenStartCol := colNumber

    def endToken():
        def pos := position
        def tok := if (input =~ s :Str) {
            s.slice(startPos, pos)
        } else {
            _makeStr.fromChars(input.slice(startPos, pos))
        }
        def span := _makeSourceSpan(inputName, tokenStartLine == lineNumber,
                    tokenStartLine, tokenStartCol, lineNumber, colNumber)
        startPos := -1
        return [tok, span]

    def leaf(tokname):
        def [tokdata, span] := endToken()
        # XXX compat with tests, fix em later
        def d := if (tokname == tokdata || tokname == "EOL") {null} else {tokdata}
        return composite(tokname, d, span)

    def collectDigits(var digitset):
        if (atEnd() || !digitset.contains(currentChar)):
            return false
        digitset |= ['_'].asSet()
        while (!atEnd() && digitset.contains(currentChar)):
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
                    throw.eject(fail, ["Missing fractional part", spanAtPoint()])
                if (decimalDigits.contains(pc)):
                    advance()
                    floating := true
                    collectDigits(decimalDigits)
            if (currentChar == 'e' || currentChar == 'E'):
                advance()
                floating := true
                if (currentChar == '-' || currentChar == '+'):
                    advance()
                if (!collectDigits(decimalDigits)):
                    throw.eject(fail, ["Missing exponent", spanAtPoint()])
        def [tok, span] := endToken()
        def s := tok.replace("_", "")
        if (floating):
            return composite(".float64.", _makeDouble(s), span)
        else:
            if (radix == 16):
                return composite(".int.", _makeInt.withRadix(16)(s.slice(2)), span)
            else:
                return composite(".int.", _makeInt(s), span)


    def charConstant(fail):
        if (currentChar == '\\'):
            def nex := advance()
            if (nex == 'U'):
                def hexstr := _makeStr.fromChars([
                    advance(), advance(), advance(), advance(),
                    advance(), advance(), advance(), advance()])
                def v := escape ej {
                    _makeInt.withRadix(16)(hexstr, ej)
                } catch _ {
                    throw.eject(fail, ["\\U escape must be eight hex digits, not " + hexstr, spanAtPoint()])
                }
                advance()
                return '\x00' + v
            if (nex == 'u'):
                def hexstr := _makeStr.fromChars([advance(), advance(), advance(), advance()])
                def v := escape ej {
                    _makeInt.withRadix(16)(hexstr, ej)
                } catch _ {
                    throw.eject(fail, ["\\u escape must be four hex digits", spanAtPoint()])
                }
                advance()
                return '\x00' + v
            else if (nex == 'x'):
                def hexstr := _makeStr.fromChars([advance(), advance()])
                def v := escape ej {
                    _makeInt.withRadix(16)(hexstr, ej)
                } catch _ {
                    throw.eject(fail, ["\\x escape must be two hex digits", spanAtPoint()])
                }
                advance()
                return '\x00' + v
            else if (nex == EOF):
                throw.eject(fail, ["End of input in middle of literal", spanAtPoint()])
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
                throw.eject(fail, [`Unrecognized escape character ${quote(nex)}`, spanAtPoint()])
            else:
                advance()
                return c
        if (currentChar == EOF):
            throw.eject(fail, ["End of input in middle of literal", spanAtPoint()])
        else if (currentChar == '\t'):
            throw.eject(fail, ["Quoted tabs must be written as \\t", spanAtPoint()])
        else if (currentChar == '\x1b'):
            throw.eject(fail, ["Quoted ESC must be written as \\x1b", spanAtPoint()])
        else:
            def c := currentChar
            advance()
            return c

    def stringLiteral(fail):
        def opener := currentChar
        advance()
        pushBrace(opener, spanAtPoint(), '"', 0, false)
        def buf := [].diverge()
        while (currentChar != '"'):
            if (atEnd()):
                throw.eject(fail, ["Input ends inside string literal", braceStack.last()[1]])
            def cc := charConstant(fail)
            if (cc != null):
               buf.push(cc)
        advance()
        return _makeStr.fromChars(buf.snapshot())

    def charLiteral(fail):
        advance()
        var c := charConstant(fail)
        while (c == null):
           c := charConstant(fail)
        if (currentChar != '\''):
            throw.eject(fail, ["Character constant must end in \"'\"", braceStack.last()[1]])
        advance()
        return composite(".char.", c, endToken()[1])

    def identifier(fail):
        while (isIdentifierPart(advance())):
            pass
        if (currentChar == '='):
            def c := peekChar()
            if (!['=', '>', '~'].contains(c)):
                advance()
                def [chunk, span] := endToken()
                def token := chunk.slice(0, chunk.size() - 1)
                if (MONTE_KEYWORDS.contains(token)):
                    throw.eject(fail, [`$token is a keyword`, spanAtPoint()])
                return composite("VERB_ASSIGN", token, span)
        def [token, span] := endToken()
        if (MONTE_KEYWORDS.contains(token.toLowerCase())):
            return composite(token.toLowerCase(), token.toLowerCase(), span)
        else:
            return composite("IDENTIFIER", token, span)

    def quasiPart(fail):
        def buf := [].diverge()
        while (true):
            while (!['@', '$', '`'].contains(currentChar)):
                # stuff that doesn't start with @ or $ passes through
                if (currentChar == EOF):
                    throw.eject(fail, ["File ends inside quasiliteral", spanAtPoint()])
                buf.push(currentChar)
                advance()
            if (peekChar() == currentChar):
                buf.push(currentChar)
                advance()
                advance()
            else if (currentChar == '`'):
                # close backtick
                advance()
                popBrace('`', fail)
                return composite("QUASI_CLOSE", _makeStr.fromChars(buf.snapshot()),
                                 endToken()[1])
            else if (currentChar == '$' && peekChar() == '\\'):
                # it's a character constant like $\u2603 or a line continuation like $\
                advance()
                def cc := charConstant(fail)
                if (cc != null):
                    buf.push(cc)
            else:
                def [opener, span] := endToken()
                pushBrace(opener, spanAtPoint(), "hole", nestLevel * 4, true)
                return composite("QUASI_OPEN", _makeStr.fromChars(buf.snapshot()),
                                 span)


    def openBracket(closer, var opener, _fail):
        var span := null
        if (opener == null):
            advance()
            def [o, s] := endToken()
            opener := o
            span := s
        if (atLogicalEndOfLine()):
            pushBrace(opener, spanAtPoint(), closer, nestLevel * 4, true)
        else:
            pushBrace(opener, spanAtPoint(), closer, offsetInLine(), true)
        return composite(opener, null, if (span != null) {span} else {spanAtPoint()})

    def closeBracket(fail):
        advance()
        def [closer, span] := endToken()
        popBrace(closer, fail)
        return composite(closer, null, span)

    def consumeComment(fail):
        def startCol := colNumber
        while (!['\n', EOF].contains(currentChar)):
            if (currentChar == '\x1b'):
                throw.eject(fail, ["ESC characters are not allowed in Monte source.", spanAtPoint()])
            advance()
        def [comment, _] := endToken()
        return composite("#", comment.slice(1), _makeSourceSpan(inputName, true, lineNumber, startCol, lineNumber, colNumber))

    def consumeWhitespaceAndComments(fail):
        var startLine := lineNumber
        var startCol := colNumber
        var spaces := skipSpaces()
        while (currentChar == '\n'):
            queuedTokens.insert(0, composite("EOL", null, _makeSourceSpan(inputName, false, startLine, startCol, lineNumber, colNumber)))
            advance()
            spaces := skipSpaces()
            if (currentChar == '#'):
                queuedTokens.insert(0, consumeComment(fail))
                startToken()
                spaces := null
            startLine := lineNumber
            startCol := colNumber
        return spaces


    def checkParenBalance

    def getNextToken(strict, fail, partialFail):
        # 'strict' determines if indentation errors count as failures; this is
        # turned off when just doing parens-balance checks.
        if (queuedTokens.size() > 0):
            return queuedTokens.pop()

        if (braceStack.last()[2] == '`'):
            startToken()
            return quasiPart(fail)

        skipSpaces()
        startToken()

        def cur := currentChar
        if (cur == EOF):
            throw.eject(fail, null)
        if (cur == '\n'):
            advance()
            if (canStartIndentedBlock):
                def spaces := consumeWhitespaceAndComments(fail)
                if (strict && !inStatementPosition()):
                    throw.eject(fail,
                        makeParseError(["Indented blocks only allowed in statement position", spanAtPoint()]))
                if (spaces > indentPositionStack.last()):
                    indentPositionStack.push(spaces)
                    openBracket("DEDENT", "INDENT", fail)
                    canStartIndentedBlock := false
                    queuedTokens.insert(0, composite("INDENT", null, spanAtPoint()))
                    return leaf("EOL")
                else if (strict):
                    throw.eject(partialFail, makeParseError(["Expected an indented block", spanAtPoint()]))
            if (!inStatementPosition()):
                return leaf("EOL")
            else:
                queuedTokens.insert(0, leaf("EOL"))
                startToken()
                def spaces := consumeWhitespaceAndComments(fail)
                if (strict && spaces > indentPositionStack.last()):
                    throw.eject(fail, ["Unexpected indent", spanAtPoint()])
                if (atEnd()):
                    while (indentPositionStack.size() > 1):
                        indentPositionStack.pop()
                        popBrace("DEDENT", fail)
                        queuedTokens.push(composite("DEDENT", null, spanAtPoint()))
                    return queuedTokens.pop()
                while (spaces < indentPositionStack.last()):
                    if (strict && !indentPositionStack.contains(spaces)):
                        throw.eject(fail, ["unindent does not match any outer indentation level", spanAtPoint()])
                    indentPositionStack.pop()
                    popBrace("DEDENT", fail)
                    queuedTokens.push(composite("DEDENT", null, null))
                return queuedTokens.pop()


        if ([';', ',', '~', '?'].contains(cur)):
            advance()
            return leaf(_makeStr.fromChars([cur]))

        if (cur == '('):
            return openBracket(")", null, fail)
        if (cur == '['):
            return openBracket("]", null, fail)
        if (cur == '{'):
            return openBracket("}", null, fail)

        if (cur == '}'):
            def result := closeBracket(fail)
            if (braceStack.last()[2] == "hole"):
                popBrace("hole", fail)
            return result
        if (cur == ']'):
            return closeBracket(fail)
        if (cur == ')'):
            return closeBracket(fail)

        if (cur == '$'):
            def nex := advance()
            if (nex == '{'):
                # quasi hole of form ${blah}
                return openBracket("}", null, fail)
            else if (nex != EOF && idStart.contains(nex)):
                # quasi hole of form $blee
                var cc := advance()
                while (isIdentifierPart(cc)):
                    cc := advance()
                def [name, span] := endToken()
                def key := name.slice(1)
                if (MONTE_KEYWORDS.contains(key.toLowerCase())):
                    advance()
                    throw.eject(fail, [`$key is a keyword`, spanAtPoint()])
                if (braceStack.last()[2] == "hole"):
                    popBrace("hole", fail)
                return composite("DOLLAR_IDENT", key, span)
            else if (nex == '$'):
                return leaf("$")
            else:
                throw.eject(fail, [`Unrecognized $$-escape "$$$nex"`, spanAtPoint()])

        if (cur == '@'):
            def nex := advance()
            if (nex == '{'):
                # quasi hole of the form @{blee}
                return openBracket("}", null, fail)
            else if (nex != EOF && idStart.contains(nex)):
                # quasi hole of the form @blee
                var cc := advance()
                while (isIdentifierPart(cc)):
                    cc := advance()
                def [name, span] := endToken()
                def key := name.slice(1)
                if (MONTE_KEYWORDS.contains(key.toLowerCase())):
                    advance()
                    throw.eject(fail, [`$key is a keyword`, spanAtPoint()])
                if (braceStack.last()[2] == "hole"):
                    popBrace("hole", fail)
                return composite("AT_IDENT", key, span)
            else if (nex == '@'):
                return leaf("@")
            else:
                throw.eject(fail, [`Unrecognized @@-escape "@@$nex"`, spanAtPoint()])

        if (cur == '.'):
            def nex := advance()
            if (nex == '.'):
                def nex2 := advance()
                if (nex2 == '!'):
                    advance()
                    return leaf("..!")
                return leaf("..")
            return leaf(".")

        if (cur == '^'):
            def nex := advance()
            if (nex == '='):
                advance()
                return leaf("^=")
            return leaf("^")

        if (cur == '+'):
            def nex := advance()
            if (nex == '+'):
                advance()
                throw.eject(fail, ["++? lol no", spanAtPoint()])
            if (nex == '='):
                advance()
                return leaf("+=")
            return leaf("+")

        if (cur == '-'):
            def nex := advance()
            if (nex == '-'):
                advance()
                throw.eject(fail, ["--? lol no", spanAtPoint()])
            if (nex == '='):
                advance()
                return leaf("-=")
            if (nex == '>'):
                advance()
                if (atLogicalEndOfLine()):
                    # this is an arrow ending a line, and should be
                    # followed by an indent
                    canStartIndentedBlock := true
                return leaf("->")
            return leaf("-")
        if (cur == ':'):
            def nex := advance()
            if (nex == ':'):
                advance()
                return leaf("::")
            if (nex == '='):
                advance()
                return leaf(":=")
            if (atLogicalEndOfLine()):
                # this is a colon ending a line, and should be
                # followed by an indent
                canStartIndentedBlock := true
            return leaf(":")

        if (cur == '<'):
            def nex := advance()
            if (nex == '-'):
                advance()
                return leaf("<-")
            if (nex == '='):
                def nex2 := advance()
                if (nex2 == '>'):
                    advance()
                    return leaf("<=>")
                return leaf("<=")

            if (nex == '<'):
                def nex2 := advance()
                if (nex2 == '='):
                    advance()
                    return leaf("<<=")
                return leaf("<<")
            return leaf("<")

        if (cur == '>'):
            def nex := advance()
            if (nex == '='):
                advance()
                return leaf(">=")
            if (nex == '>'):
                def nex2 := advance()
                if (nex2 == '='):
                    advance()
                    return leaf(">>=")
                return leaf(">>")
            return leaf(">")

        if (cur == '*'):
            def nex := advance()
            if (nex == '*'):
                def nex2 := advance()
                if (nex2 == '='):
                    advance()
                    return leaf("**=")
                return leaf("**")
            if (nex == '='):
                advance()
                return leaf("*=")
            return leaf("*")

        if (cur == '/'):
            def nex := advance()
            if (nex == '/'):
                def nex2 := advance()
                if (nex2 == '='):
                    advance()
                    return leaf("//=")
                return leaf("//")
            if (nex == '='):
                advance()
                return leaf("/=")
            return leaf("/")

        if (cur == '#'):
            return consumeComment(fail)

        if (cur == '%'):
            def nex := advance()
            if (nex == '='):
                advance()
                return leaf("%=")
            return leaf("%")

        if (cur == '!'):
            def nex := advance()
            if (nex == '='):
                advance()
                return leaf("!=")
            if (nex == '~'):
                advance()
                return leaf("!~")
            return leaf("!")

        if (cur == '='):
            def nex := advance()
            if (nex == '='):
                advance()
                return leaf("==")
            if (nex == '>'):
                advance()
                return leaf("=>")
            if (nex == '~'):
                advance()
                return leaf("=~")
            throw.eject(fail, ["Use := for assignment or == for equality", spanAtPoint()])
        if (cur == '&'):
            def nex := advance()
            if (nex == '&'):
                advance()
                return leaf("&&")
            if (nex == '='):
                advance()
                return leaf("&=")
            if (nex == '!'):
                advance()
                return leaf("&!")
            return leaf("&")

        if (cur == '|'):
            def nex := advance()
            if (nex == '='):
                advance()
                return leaf("|=")
            if (nex == '|'):
                advance()
                return leaf("||")
            return leaf("|")

        if (cur == '"'):
            def s := stringLiteral(fail)
            def [_closer, span] := endToken()
            popBrace('"', fail)

            return composite(".String.", s, span)

        if (cur == '\''):
            return charLiteral(fail)

        if (cur == '`'):
            advance()
            pushBrace('`', spanAtPoint(), '`', 0, false)
            def part := quasiPart(fail)
            if (part == null):
                def next := getNextToken(strict, fail, partialFail)
                if (next == EOF):
                    throw.eject(fail, ["File ends in quasiliteral", spanAtPoint()])
                return next
            return part

        if (decimalDigits.contains(cur)):
            return numberLiteral(fail)

        if (cur == '_'):
            def pc := peekChar()
            if (pc != EOF && idStart.contains(pc)):
                return identifier(fail)
            advance()
            return leaf("_")

        if (cur == '\t'):
            throw.eject(fail, ["Tab characters are not permitted in Monte source.", spanAtPoint()])
        if (idStart.contains(cur)):
            return identifier(fail)

        if (cur =~ [hole ? ([VALUE_HOLE, PATTERN_HOLE].contains(hole)),
                    index :Int, _]):
            advance()
            return [[hole, index], spanAtPoint()]

        throw.eject(fail, [`Unrecognized character ${quote(cur)}`, spanAtPoint()])

    bind checkParenBalance(fail):
        while (true):
            startPos := -1
            getNextToken(false, __break, __break)
        if (braceStack.size() != 0):
            for b in (braceStack):
                if (!["INDENT", null].contains(b[0])):
                    throw.eject(fail, [`No matching ${b[2]} found`, b[1]])

    advance()
    return object monteLexer:

        to _makeIterator():
            return monteLexer

        to getSyntaxError():
            return errorMessage

        to valueHole():
            return VALUE_HOLE

        to patternHole():
            return PATTERN_HOLE

        to next(ej, ejPartial):
            try:
                def errorStartPos := position
                escape e:
                    def t := getNextToken(true, e, ejPartial)
                    return [count += 1, t]
                catch msg:
                    if (msg == null):
                        checkParenBalance(fn msg {throw.eject(ejPartial, makeParseError(msg))})
                        throw.eject(ej, null)
                    else:
                        throw.eject(ej, makeParseError(msg))
            finally:
                startPos := -1

        to lexerForNextChunk(chunk):
            return _makeMonteLexer(chunk, braceStack, nestLevel, inputName)

        to makeParseError(e):
            return makeParseError(e)

        to getInput():
            return input

        match [=="next", [ej], _]:
            monteLexer.next(ej, ej)

object makeMonteLexer as DeepFrozen:
    to run(input, inputName):
        # State for paired delimiters like "", {}, (), []
        def braceStack := [[null, null, null, 0, true]].diverge()
        return _makeMonteLexer(input, braceStack, 0, inputName)

    to holes():
        return [VALUE_HOLE, PATTERN_HOLE]
