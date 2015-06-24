object VALUE_HOLE {}
object PATTERN_HOLE {}
object EOF {}
def decimalDigits := '0'..'9'
def hexDigits := decimalDigits | 'a'..'f' | 'A'..'F'

def idStart := 'a'..'z' | 'A'..'Z' | '_'..'_'
def idPart := idStart | '0'..'9'
def closers := ['(' => ')', '[' => ']', '{' => '}']

def isIdentifierPart(c):
    if (c == EOF):
        return false
    return idPart(c)

def MONTE_KEYWORDS := [
    "as", "bind", "break", "catch", "continue", "def", "else", "escape",
    "exit", "extends", "export", "finally", "fn", "for", "guards", "if",
    "implements", "in", "interface", "match", "meta", "method", "module",
    "object", "pass", "pragma", "return", "switch", "to", "try", "var",
    "via", "when", "while"]

def composite(name, data, span):
    return term__quasiParser.makeTerm(term__quasiParser.makeTag(null, name, Any),
                                      data, [], span)

def _makeMonteLexer(input, braceStack, var nestLevel):

    # The character under the cursor.
    var currentChar := null
    # Offset of the current character.
    var position := -1
    # Start offset of the text for the token being created.
    var startPos := -1

    # Syntax error produced from most recent tokenization attempt.
    var errorMessage := null

    var count := -1

    var canStartIndentedBlock := false
    def queuedTokens := [].diverge()
    def indentPositionStack := [0].diverge()

    def atEnd():
        return position == input.size()

    def spanAtPoint():
        return position
        def inp := if (input.getSpan() == null) {
            input.asFrom("<input>")
            input
        } else {
            input
        }
        return inp.slice(0.max(position - 1), 1.max(position)).getSpan()

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
            throw.eject(fail, [`Unmatched closing character ${closer.quote()}`, spanAtPoint()])
        else if (braceStack.last()[1] != closer):
            throw.eject(fail, [`Mismatch: ${closer.quote()} doesn't close ${braceStack.last()[0]}`, spanAtPoint()])
        def item := braceStack.pop()
        if (item[3]):
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

    def endToken():
        def pos := position
        def tok := input.slice(startPos, pos)
        startPos := -1
        return tok

    def leaf(tok):
        return composite(tok, null, endToken().getSpan())

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
                    throw.eject(fail, ["Missing fractional part", spanAtPoint()])
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
                    throw.eject(fail, ["Missing exponent", spanAtPoint()])
        def tok := endToken()
        def s := tok.replace("_", "")
        if (floating):
            return composite(".float64.", __makeDouble(s), tok.getSpan())
        else:
            if (radix == 16):
                return composite(".int.", __makeInt(s.slice(2), 16), tok.getSpan())
            else:
                return composite(".int.", __makeInt(s), tok.getSpan())


    def charConstant(fail):
        if (currentChar == '\\'):
            def nex := advance()
            if (nex == 'U'):
                def hexstr := __makeString.fromChars([
                    advance(), advance(), advance(), advance(),
                    advance(), advance(), advance(), advance()])
                def v := try {
                    __makeInt(hexstr, 16)
                } catch _ {
                    throw.eject(fail, ["\\U escape must be eight hex digits, not " + hexstr, spanAtPoint()])
                }
                advance()
                return '\x00' + v
            if (nex == 'u'):
                def hexstr := __makeString.fromChars([advance(), advance(), advance(), advance()])
                def v := try {
                    __makeInt(hexstr, 16)
                } catch _ {
                    throw.eject(fail, ["\\u escape must be four hex digits", spanAtPoint()])
                }
                advance()
                return '\x00' + v
            else if (nex == 'x'):
                def v := try {
                    __makeInt(__makeString.fromChars([advance(), advance()]), 16)
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
                throw.eject(fail, [`Unrecognized escape character ${nex.quote()}`, spanAtPoint()])
            else:
                advance()
                return c
        if (currentChar == EOF):
            throw.eject(fail, ["End of input in middle of literal", spanAtPoint()])
        else if (currentChar == '\t'):
            throw.eject(fail, ["Quoted tabs must be written as \\t", spanAtPoint()])
        else:
            def c := currentChar
            advance()
            return c

    def stringLiteral(fail):
        def opener := currentChar
        advance()
        pushBrace(opener, '"', 0, false)
        def buf := [].diverge()
        while (currentChar != '"'):
            if (atEnd()):
                throw.eject(fail, ["Input ends inside string literal", spanAtPoint()])
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
            throw.eject(fail, ["Character constant must end in \"'\"", spanAtPoint()])
        advance()
        return composite(".char.", c, endToken().getSpan())

    def identifier(fail):
        while (isIdentifierPart(advance())):
            pass
        if (currentChar == '='):
            def c := peekChar()
            if (!['=', '>', '~'].contains(c)):
                advance()
                def chunk := endToken()
                def token := chunk.slice(0, chunk.size() - 1)
                if (MONTE_KEYWORDS.contains(token)):
                    throw.eject(fail, [`$token is a keyword`, spanAtPoint()])
                return composite("VERB_ASSIGN", token, chunk.getSpan())
        def token := endToken()
        if (MONTE_KEYWORDS.contains(token.toLowerCase())):
            return composite(token.toLowerCase(), token.toLowerCase(), token.getSpan())
        else:
            return composite("IDENTIFIER", token, token.getSpan())

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
                return composite("QUASI_CLOSE", __makeString.fromChars(buf.snapshot()),
                                 endToken().getSpan())
            else if (currentChar == '$' && peekChar() == '\\'):
                # it's a character constant like $\u2603 or a line continuation like $\
                advance()
                def cc := charConstant(fail)
                if (cc != null):
                    buf.push(cc)
            else:
                def opener := endToken()
                pushBrace(opener, "hole", nestLevel * 4, true)
                return composite("QUASI_OPEN", __makeString.fromChars(buf.snapshot()),
                                 opener.getSpan())


    def openBracket(closer, var opener, fail):
        if (opener == null):
            advance()
            opener := endToken()
        if (atLogicalEndOfLine()):
            pushBrace(opener, closer, nestLevel * 4, true)
        else:
            pushBrace(opener, closer, offsetInLine(), true)
        return composite(opener, null, opener.getSpan())

    def closeBracket(fail):
        advance()
        def closer := endToken()
        popBrace(closer, fail)
        return composite(closer, null, closer.getSpan())

    def consumeComment():
        while (!['\n', EOF].contains(currentChar)):
            advance()
        def comment := endToken()
        return composite("#", comment.slice(1), comment.getSpan())

    def consumeWhitespaceAndComments():
        var spaces := skipSpaces()
        while (currentChar == '\n'):
            queuedTokens.insert(0, composite("EOL", null, input.slice(position, position + 1).getSpan()))
            advance()
            spaces := skipSpaces()
            if (currentChar == '#'):
                queuedTokens.insert(0, consumeComment())
                startToken()
                spaces := null
        return spaces


    def getNextToken(fail):
        if (queuedTokens.size() > 0):
            return queuedTokens.pop()

        if (braceStack.last()[1] == '`'):
            startToken()
            return quasiPart(fail)

        skipSpaces()
        startToken()

        def cur := currentChar
        if (cur == EOF):
            throw.eject(fail, null)
        if (cur == '\n'):
            def c := advance()
            if (canStartIndentedBlock):
                def spaces := consumeWhitespaceAndComments()
                if (!inStatementPosition()):
                    throw.eject(fail,
                        ["Indented blocks only allowed in statement position", spanAtPoint()])
                if (spaces > indentPositionStack.last()):
                    indentPositionStack.push(spaces)
                    openBracket("DEDENT", "INDENT", fail)
                    canStartIndentedBlock := false
                    queuedTokens.insert(0, composite("INDENT", null, null))
                    return leaf("EOL")
                else:
                    throw.eject(fail, ["Expected an indented block", spanAtPoint()])
            if (!inStatementPosition()):
                return leaf("EOL")
            else:
                queuedTokens.insert(0, leaf("EOL"))
                startToken()
                def spaces := consumeWhitespaceAndComments()
                if (spaces > indentPositionStack.last()):
                    throw.eject(fail, ["Unexpected indent", spanAtPoint()])
                if (atEnd()):
                    while (indentPositionStack.size() > 1):
                        indentPositionStack.pop()
                        popBrace("DEDENT", fail)
                        queuedTokens.push(composite("DEDENT", null, null))
                    return queuedTokens.pop()
                while (spaces < indentPositionStack.last()):
                    if (!indentPositionStack.contains(spaces)):
                        throw.eject(fail, ["unindent does not match any outer indentation level", spanAtPoint()])
                    indentPositionStack.pop()
                    popBrace("DEDENT", fail)
                    queuedTokens.push(composite("DEDENT", null, null))
                return queuedTokens.pop()


        if ([';', ',', '~', '?'].contains(cur)):
            advance()
            return leaf(__makeString.fromChars([cur]))

        if (cur == '('):
            return openBracket(")", null, fail)
        if (cur == '['):
            return openBracket("]", null, fail)
        if (cur == '{'):
            return openBracket("}", null, fail)

        if (cur == '}'):
            def result := closeBracket(fail)
            if (braceStack.last()[1] == "hole"):
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
            else if (nex != EOF && idStart(nex)):
                # quasi hole of form $blee
                var cc := advance()
                while (isIdentifierPart(cc)):
                    cc := advance()
                def name := endToken()
                def key := name.slice(1)
                if (MONTE_KEYWORDS.contains(key.toLowerCase())):
                    advance()
                    throw.eject(fail, [`$key is a keyword`, spanAtPoint()])
                if (braceStack.last()[1] == "hole"):
                    popBrace("hole", fail)
                return composite("DOLLAR_IDENT", key, name.getSpan())
            else if (nex == '$'):
                return leaf("$")
            else:
                throw.eject(fail, [`Unrecognized $$-escape "$$$nex"`, spanAtPoint()])

        if (cur == '@'):
            def nex := advance()
            if (nex == '{'):
                # quasi hole of the form @{blee}
                return openBracket("}", null, fail)
            else if (nex != EOF && idStart(nex)):
                # quasi hole of the form @blee
                var cc := advance()
                while (isIdentifierPart(cc)):
                    cc := advance()
                def name := endToken()
                def key := name.slice(1)
                if (MONTE_KEYWORDS.contains(key.toLowerCase())):
                    advance()
                    throw.eject(fail, [`$key is a keyword`, spanAtPoint()])
                if (braceStack.last()[1] == "hole"):
                    popBrace("hole", fail)
                return composite("AT_IDENT", key, name.getSpan())
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
            return consumeComment()

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
            def closer := endToken()
            popBrace('"', fail)

            return composite(".String.", s, closer.getSpan())

        if (cur == '\''):
            return charLiteral(fail)

        if (cur == '`'):
            advance()
            pushBrace('`', '`', 0, false)
            def part := quasiPart(fail)
            if (part == null):
                def next := getNextToken(fail)
                if (next == EOF):
                    throw.eject(fail, ["File ends in quasiliteral", spanAtPoint()])
                return next
            return part

        if (decimalDigits(cur)):
            return numberLiteral(fail)

        if (cur == '_'):
            def pc := peekChar()
            if (pc != EOF && idStart(pc)):
                return identifier(fail)
            advance()
            return leaf("_")

        if (cur == '\t'):
            throw.eject(fail, ["Tab characters are not permitted in Monte source.", spanAtPoint()])
        if (idStart(cur)):
            return identifier(fail)

        throw.eject(fail, [`Unrecognized character ${cur.quote()}`, spanAtPoint()])

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

        to next(ej):
            try:
                def errorStartPos := position
                escape e:
                    def t := getNextToken(e)
                    return [count += 1, t]
                catch msg:
                    errorMessage := msg
                    if (msg == null && !atEnd()):
                        throw.eject(ej, [`Trailing garbage: ${input.slice(position, input.size())}`, spanAtPoint()])
                    throw.eject(ej, msg)
            finally:
                startPos := -1

        to lexerForNextChunk(chunk):
            return _makeMonteLexer(chunk, braceStack, nestLevel)


object makeMonteLexer:
    to run(input):
        # State for paired delimiters like "", {}, (), []
        def braceStack := [[null, null, 0, true]].diverge()
        return _makeMonteLexer(input, braceStack, 0)

    to holes():
        return [VALUE_HOLE, PATTERN_HOLE]


[=> makeMonteLexer]
