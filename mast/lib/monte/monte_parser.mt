exports (parseModule, parseExpression, parsePattern)

def spanCover(left, right) as DeepFrozen:
    if (left == null || right == null):
        return null
    return left.combine(right)

def parseMonte(lex, builder, mode, err, errPartial) as DeepFrozen:
    def [VALUE_HOLE, PATTERN_HOLE] := [lex.valueHole(), lex.patternHole()]
    def _toks := [].diverge()
    while (true):
         _toks.push(lex.next(__break, errPartial)[1])
    catch p:
        if (p != null):
            throw.eject(err, p)
    def tokens := _toks.snapshot()
    var position := -1
    var lastError := null

    def formatError(var error, ej):
        if (error == null):
            error := ["Syntax error", tokens[position][2]]
        throw.eject(ej, lex.makeParseError(error))

    def giveUp(e):
        formatError(e, err)

    def spanHere():
        return if (position + 1 >= tokens.size()):
            null
        else:
            tokens[position.max(0)][2]

    def spanNext():
        return if (position + 2 >= tokens.size()):
            null
        else:
            tokens[position + 1][2]

    def spanFrom(start):
        return spanCover(start, spanHere())

    def advance(ej):
        position += 1
        if (position >= tokens.size()):
            throw.eject(ej, ["hit EOF", tokens.last()[2]])
        def t := tokens[position]
        return t

    def advanceTag(ej):
        def t := advance(ej)
        return t[0]

    def acceptTag(tagname, fail):
        def t := advance(fail)
        def specname := t[0]
        if (specname != tagname):
            position -= 1
            throw.eject(fail,
                [`expected ${M.toQuote(tagname)}, got ${M.toQuote(specname)}`,
                 t[2]])
        return t

    def acceptEOLs():
        while (true):
            if ((position + 1) >= tokens.size()):
                return
            def t := tokens[position + 1]
            if (!["EOL", "#"].contains(t[0])):
                return
            position += 1

    # Forward-declared really early in order to be usable in combinators.
    def expr

    def acceptParenExpr(fail):
        "
        Accept a parenthesized expression, or fail.

        The expression will unconditionally be bracketed by a pair of
        parentheses.
        "

        def [open, _, openSpan] := advance(fail)
        if (open != "("):
            position -= 1
            throw.eject(fail,
                [`expected '(' for start of parenthesized expression, got ${M.toQuote(open)}`,
                 openSpan])
        # We allow EOLs here in order to permit long non-seq-exprs to have
        # their own long line to themselves.
        acceptEOLs()
        def rv := expr(fail)
        # Here too, so that parens don't have to be cuddled Lisp-style.
        acceptEOLs()
        def [close, _, closeSpan] := advance(fail)
        if (close != ")"):
            position -= 1
            throw.eject(fail,
                [`expected ')' for end of parenthesized expression, got ${M.toQuote(close)}`,
                 closeSpan])
        return rv

    def peek():
        return if (position + 1 >= tokens.size()):
            null
        else:
            tokens[position + 1]

    def opt(rule, _ej):
        return escape e { rule(e) } catch _ { null }

    def peekTag():
        if (position + 1 >= tokens.size()):
            return null
        def t := tokens[position + 1]
        return t[0]

    def considerTag(tagName, ej) :Bool:
        "
        Advances if the next tag matches `tagName`.

        Returns whether we advanced.
        "

        return if (peekTag() == tagName):
            advance(ej)
            true
        else:
            false

    def matchEOLsThenTag(indent, tagname):
        def origPosition := position
        if (indent):
            acceptEOLs()
        return if (position + 1 >= tokens.size()):
            position := origPosition
            false
        else if (tokens[position + 1][0] == tagname):
            position += 1
            true
        else:
            position := origPosition
            false

    def acceptVerb(ej):
        return if (peekTag() == ".String.") {
            advance(ej)[1]
        } else {
            def t := acceptTag("IDENTIFIER", ej)
            _makeStr.fromStr(t[1], t[2])
        }

    def acceptList(rule):
        acceptEOLs()
        def items := [].diverge()
        escape e:
            items.push(rule(e))
            while (true):
                acceptTag(",", __break)
                acceptEOLs()
                items.push(rule(__break))
            catch msg:
                lastError := msg
        return items.snapshot()

    def acceptListOrMap(ruleList, ruleMap):
        var isMap := false
        def items := [].diverge()
        def startpos := position
        acceptEOLs()
        escape em:
            items.push(ruleMap(em))
            isMap := true
        catch _:
            escape e:
                position := startpos
                items.push(ruleList(e))
                isMap := false
            catch _:
                return [[], false]
        while (true):
            acceptTag(",", __break)
            acceptEOLs()
            if (isMap):
                items.push(ruleMap(__break))
            else:
                items.push(ruleList(__break))
        catch msg:
            lastError := msg

        return [items.snapshot(), isMap]

    def order
    def comp
    def blockExpr
    def prim
    def pattern
    def assign
    def quasiliteral(id, isPattern, ej):
        def spanStart := if (id == null) {spanHere()} else {id[2]}
        def name := if (id == null) {null} else {id[1]}
        def parts := [].diverge()
        while (true):
            def t := advance(ej)
            def tname := t[0]
            if (tname == "QUASI_OPEN" && t[1] != ""):
                parts.push(builder.QuasiText(t[1], t[2]))
            else if (tname == "QUASI_CLOSE"):
                parts.push(builder.QuasiText(t[1], t[2]))
                break
            else if (tname == "DOLLAR_IDENT"):
                parts.push(builder.QuasiExprHole(
                               builder.NounExpr(t[1], t[2]),
                               t[2]))
            else if (tname == "${"):
                def subexpr := expr(ej)
                parts.push(builder.QuasiExprHole(subexpr, subexpr.getSpan()))
            else if (tname == "AT_IDENT"):
                def patt := if (t[1] == "_") {
                    builder.IgnorePattern(null, t[2])
                } else {
                    builder.FinalPattern(
                        builder.NounExpr(t[1], t[2]),
                        null, t[2])
                }
                parts.push(builder.QuasiPatternHole(patt, t[2]))
            else if (tname == "@{"):
                def subpatt := pattern(ej)
                parts.push(builder.QuasiPatternHole(subpatt, subpatt.getSpan()))
        return if (isPattern):
            builder.QuasiParserPattern(name, parts.snapshot(), spanFrom(spanStart))
        else:
            builder.QuasiParserExpr(name, parts.snapshot(), spanFrom(spanStart))

    def guard(ej):
       def spanStart := spanHere()
       return if (peekTag() == "IDENTIFIER"):
           def t := advance(ej)
           def n := builder.NounExpr(t[1], t[2])
           if (considerTag("[", ej)):
               def g := acceptList(expr)
               acceptTag("]", ej)
               builder.GetExpr(n, g, spanFrom(spanStart))
           else:
               n
       else:
           acceptParenExpr(ej)

    def nounAndName(ej):
        return if (peekTag() == VALUE_HOLE):
            [null, builder.ValueHoleExpr(advance(ej)[1], spanHere())]
        else if (peekTag() == PATTERN_HOLE):
            [null, builder.PatternHoleExpr(advance(ej)[1], spanHere())]
        else if (peekTag() == "IDENTIFIER"):
            def t := advance(ej)
            [t[1], builder.NounExpr(t[1], t[2])]
        else:
            def spanStart := spanHere()
            acceptTag("::", ej)
            def t := acceptTag(".String.", ej)
            [t[1], builder.NounExpr(t[1], spanFrom(spanStart))]

    def noun(ej):
        return nounAndName(ej)[1]

    def maybeGuard():
        def origPosition := position
        if (considerTag(":", null)):
            return escape e:
                guard(e)
            catch _:
                # might be suite-starting colon
                position := origPosition
                null

    def strictNamePattern(ej):
        def spanStart := spanHere()
        def nex := peekTag()
        return if (nex == "IDENTIFIER"):
            def t := advance(ej)
            def g := maybeGuard()
            [t[1], builder.FinalPattern(builder.NounExpr(t[1], t[2]), g, spanFrom(spanStart))]
        else if (nex == "::"):
            advance(ej)
            def spanStart := spanHere()
            def t := acceptTag(".String.", ej)
            def g := maybeGuard()
            [t[1], builder.FinalPattern(builder.NounExpr(t[1], t[2]), g, spanFrom(spanStart))]
        else if (nex == "var"):
            advance(ej)
            def [name, n] := nounAndName(ej)
            def g := maybeGuard()
            [name, builder.VarPattern(n, g, spanFrom(spanStart))]
        else if (nex == "&"):
            advance(ej)
            def [name, n] := nounAndName(ej)
            def g := maybeGuard()
            ["&" + name, builder.SlotPattern(n, g, spanFrom(spanStart))]
        else if (nex == "&&"):
            advance(ej)
            def [name, n] := nounAndName(ej)
            ["&&" + name, builder.BindingPattern(n, spanFrom(spanStart))]
        else:
            throw.eject(ej, [`Unrecognized name pattern $nex`, spanNext()])

    def namePattern(ej, tryQuasi):
        def spanStart := spanHere()
        def nex := peekTag()
        if (nex == "IDENTIFIER" && tryQuasi && position + 2 < tokens.size()):
            def nex2 := tokens[position + 2][0]
            if (nex2 == "QUASI_OPEN" || nex2 == "QUASI_CLOSE"):
                def x := quasiliteral(advance(ej), true, ej)
                return x

        escape e:
            return strictNamePattern(e)[1]

        if (nex == "bind"):
            advance(ej)
            def n := noun(ej)
            def g := maybeGuard()
            return builder.BindPattern(n, g, spanFrom(spanStart))
        else if (nex == VALUE_HOLE):
            return builder.ValueHolePattern(advance(ej)[1], spanHere())
        else if (nex == PATTERN_HOLE):
            return builder.PatternHolePattern(advance(ej)[1], spanHere())
        throw.eject(ej, [`Unrecognized name pattern $nex`, spanNext()])

    def _mapPatternItem(pairBuilder, importBuilder, ej):
        def spanStart := spanHere()
        return if (considerTag("=>", ej)):
            def p := namePattern(ej, false)
            def default := if (considerTag(":=", ej)) {
                order(ej)
            } else {null}
            importBuilder(p, default, spanFrom(spanStart))
        else:
            def k := if (considerTag("(", ej)) {
                def e := expr(ej)
                acceptEOLs()
                acceptTag(")", ej)
                e
            } else {
                if ([".String.", ".int.", ".float64.", ".char."].contains(peekTag())) {
                    def t := advance(ej)
                    builder.LiteralExpr(t[1], t[2])
                } else {
                    throw.eject(ej, ["Map pattern keys must be literals or expressions in parens", spanNext()])
                }
            }
            acceptTag("=>", ej)
            def p := pattern(ej)
            def default := if (considerTag(":=", ej)) {
                order(ej)
            } else {null}
            pairBuilder(k, p, default, spanFrom(spanStart))

    def mapPatternItem(ej):
        return _mapPatternItem(builder.MapPatternAssoc, builder.MapPatternImport, ej)

    def namedParamItem(ej):
        def spanStart := spanHere()
        def p := mapPatternItem(ej)
        return builder.NamedParam(null, p, null, spanFrom(spanStart))

    def _pattern(ej):
        escape e:
            return namePattern(e, true)
        # ... if namePattern fails, keep going
        def spanStart := spanHere()
        def nex := peekTag()
        return if (nex == "QUASI_OPEN" || nex == "QUASI_CLOSE"):
            quasiliteral(null, true, ej)
        else if (nex == "=="):
            advance(ej)
            builder.SamePattern(prim(ej), true, spanFrom(spanStart))
        else if (nex == "!="):
            advance(ej)
            builder.SamePattern(prim(ej), false, spanFrom(spanStart))
        else if (nex == "_"):
            advance(ej)
            def g := if (peekTag() == ":" && tokens[position + 2][0] != "EOL") {
                advance(ej); guard(ej)
            } else {
                null
            }
            builder.IgnorePattern(g, spanFrom(spanStart))
        else if (nex == "via"):
            advance(ej)
            def e := acceptParenExpr(ej)
            builder.ViaPattern(e, pattern(ej), spanFrom(spanStart))
        else if (nex == "["):
            advance(ej)
            def [items, isMap] := acceptListOrMap(pattern, mapPatternItem)
            acceptEOLs()
            acceptTag("]", ej)
            if (isMap):
                def tail := if (considerTag("|", ej)) {_pattern(ej)}
                builder.MapPattern(items, tail, spanFrom(spanStart))
            else:
                def tail := if (considerTag("+", ej)) {_pattern(ej)}
                builder.ListPattern(items, tail, spanFrom(spanStart))
        else if (nex == VALUE_HOLE):
            builder.ValueHolePattern(advance(ej)[1], spanHere())
        else if (nex == PATTERN_HOLE):
            builder.PatternHolePattern(advance(ej)[1], spanHere())
        else:
            throw.eject(ej, [`Invalid pattern $nex`, spanNext()])

    bind pattern(ej):
        def spanStart := spanHere()
        def p := _pattern(ej)
        return if (considerTag("?", ej)):
            def e := acceptParenExpr(ej)
            builder.SuchThatPattern(p, e, spanFrom(spanStart))
        else:
            p

    def _pairItem(mkExport, mkPair, ej):
        def spanStart := spanHere()
        return if (considerTag("=>", ej)):
            if (considerTag("&", ej)):
                mkExport(builder.SlotExpr(noun(ej), spanFrom(spanStart)), spanFrom(spanStart))
            else if (considerTag("&&", ej)):
                mkExport(builder.BindingExpr(noun(ej), spanFrom(spanStart)), spanFrom(spanStart))
            else:
                mkExport(noun(ej), spanFrom(spanStart))
        else:
            def k := expr(ej)
            acceptTag("=>", ej)
            def v := expr(ej)
            mkPair(k, v, spanFrom(spanStart))

    def mapItem(ej):
        return _pairItem(builder.MapExprExport, builder.MapExprAssoc, ej)

    def namedArg(ej):
        return _pairItem(builder.NamedArgExport, builder.NamedArg, ej)

    def seqSep(ej):
        if (![";", "#", "EOL"].contains(peekTag())):
            ej(["Expected a semicolon or newline after expression",
                tokens[position.min(tokens.size() - 1)][2]])
        advance(ej)
        while (true):
            if (![";", "#", "EOL"].contains(peekTag())):
                break
            advance(ej)

    def seq(indent, ej):
        def ex := if (indent) {blockExpr} else {expr}
        def start := spanHere()
        def exprs := [].diverge()
        exprs.push(ex(ej))
        while (true):
            seqSep(__break)
            exprs.push(ex(__break))
        catch msg:
            lastError := msg
        opt(seqSep, ej)
        return if (exprs.size() == 1):
            exprs[0]
        else:
            builder.SeqExpr(exprs.snapshot(), spanFrom(start))

    def block(indent, ej):
        if (indent):
            acceptTag(":", ej)
            acceptEOLs()
            acceptTag("INDENT", ej)
        else:
            acceptTag("{", ej)
        acceptEOLs()
        def contents := if (considerTag("pass", ej)) {
            acceptEOLs()
            builder.SeqExpr([], null)
        } else {
            escape e {
                seq(indent, e)
            } catch _ {
                builder.SeqExpr([], null)
            }
        }
        if (indent):
            acceptTag("DEDENT", ej)
        else:
            acceptTag("}", ej)
        return contents

    def suite(rule, indent, ej):
        if (indent):
            acceptTag(":", ej)
            acceptEOLs()
            acceptTag("INDENT", ej)
        else:
            acceptTag("{", ej)
        acceptEOLs()
        def content := rule(indent, ej)
        acceptEOLs()
        if (indent):
            acceptTag("DEDENT", ej)
        else:
            acceptTag("}", ej)
        return content

    def repeat(rule, indent, _ej):
        def contents := [].diverge()
        while (true):
            contents.push(rule(indent, __break))
        catch msg:
            lastError := msg
        return contents.snapshot()

    def forExprHead(ej):
        def p1 := pattern(ej)
        def p2 := if (considerTag("=>", ej)) {pattern(ej)} else {null}
        acceptEOLs()
        acceptTag("in", ej)
        acceptEOLs()
        # XXX Why yes, this *is* open-coded. This should probably be factored,
        # but I'm not sure how. ~ C.
        def [open, _, openSpan] := advance(ej)
        if (open != "("):
            position -= 1
            throw.eject(ej,
                [`expected '(' for start of for-expr iterable, got ${M.toQuote(open)}`,
                 openSpan])
        acceptEOLs()
        def it := comp(ej)
        acceptEOLs()
        def [close, _, closeSpan] := advance(ej)
        if (close != ")"):
            position -= 1
            throw.eject(ej,
                [`expected ')' for end of for-expr iterable, got ${M.toQuote(close)}`,
                 closeSpan])
        acceptEOLs()
        return if (p2 == null) {[null, p1, it]} else {[p1, p2, it]}

    def matchers(indent, ej):
        def spanStart := spanHere()
        acceptTag("match", ej)
        def pp := pattern(ej)
        def bl := block(indent, ej)
        acceptEOLs()
        return builder.Matcher(pp, bl, spanFrom(spanStart))

    def catcher(indent, ej):
        return [pattern(ej), block(indent, ej)]

    def methBody(indent, ej):
        acceptEOLs()
        def [_, doco, docoSpan] := if (peekTag() == ".String.") {
            advance(ej)
        } else {
            [null, null, null]
        }
        acceptEOLs()
        return if (!indent && peekTag() == "}"):
            [doco, builder.SeqExpr(
                if (doco == null) {[]
                } else {[builder.LiteralExpr(doco, docoSpan)]}, null)]
        else:
            var contents := seq(indent, ej)
            if (doco != null &&
                contents.getNodeName() == "SeqExpr" &&
                contents.getExprs().size() == 0):
                contents := builder.LiteralExpr(doco, docoSpan)
            [doco, contents]

    def positionalParam(ej):
        def pattStart := position
        def p := pattern(ej)
        if (peekTag() == "=>"):
            position := pattStart
            throw.eject(ej, null)
        return p

    def namedParam(ej):
        return _mapPatternItem(builder.NamedParam, builder.NamedParamImport, ej)

    def meth(indent, ej):
        acceptEOLs()
        def spanStart := spanHere()
        def mknode := if (considerTag("to", ej)) {
            builder."To"
        } else {
            acceptTag("method", ej)
            builder."Method"
        }
        def verb := acceptVerb(ej)
        acceptTag("(", ej)
        def patts := acceptList(positionalParam)
        def namedPatts := acceptList(namedParam)
        acceptTag(")", ej)
        def resultguard := if (considerTag(":", ej)) {
            if (peekTag() == "EOL") {
                # Oops, end of indenty block.
                position -= 1
                null
            } else {
                guard(ej)
            }
        } else {
            null
        }
        def [doco, body] := suite(methBody, indent, ej)
        return mknode(doco, verb, patts, namedPatts, resultguard, body, spanFrom(spanStart))

    def objectScript(indent, ej):
        def doco := if (peekTag() == ".String.") {
            advance(ej)[1]
        } else {
            null
        }
        def meths := [].diverge()
        while (true):
            acceptEOLs()
            if (["DEDENT", "}", "match"].contains(peekTag())):
                break
            if (considerTag("pass", ej)):
                continue
            meths.push(meth(indent, ej))
        def matchs := [].diverge()
        while (true):
            if (considerTag("pass", ej)):
                continue
            matchs.push(matchers(indent, __break))
        catch msg:
            acceptEOLs()
            if (!["DEDENT", "}"].contains(peekTag())):
                ej(msg)
        return [doco, meths.snapshot(), matchs.snapshot()]

    def oAuditors(ej):
        return [
            if (considerTag("as", ej)) {
                order(ej)
            } else {
                null
            },
            if (considerTag("implements", ej)) {
                acceptList(order)
            } else {
                []
            }]

    def blockLookahead(ej):
        def origPosition := position
        try:
            acceptTag(":", ej)
            acceptEOLs()
            # This may be incomplete input from the REPL or such.
            if (position == (tokens.size() - 1)):
                # If so, don't try again with braces, just stop.
                errPartial("hit EOF")
            acceptTag("INDENT", ej)
        finally:
            position := origPosition

    def objectExpr(name, indent, tryAgain, ej, spanStart):
        def oExtends := if (considerTag("extends", ej)) {
            order(ej)
        } else {
            null
        }
        def [oAs, oImplements] := oAuditors(ej)
        if (indent):
            blockLookahead(tryAgain)
        def [doco, methods, matchers] := suite(objectScript, indent, ej)
        def span := spanFrom(spanStart)
        return builder.ObjectExpr(doco, name, oAs, oImplements,
            builder.Script(oExtends, methods, matchers, span), span)

    def objectFunction(name, verb, indent, tryAgain, ej, spanStart):
        acceptTag("(", ej)
        def patts := acceptList(positionalParam)
        def namedPatts := acceptList(namedParam)
        acceptTag(")", ej)
        def resultguard := if (considerTag(":", ej)) {
            if (peekTag() == "EOL") {
                # Oops, end of indenty block.
                position -= 1
                null
            } else {
                guard(ej)
            }
        } else {
            null
        }
        def [oAs, oImplements] := oAuditors(ej)
        if (indent):
            blockLookahead(tryAgain)
        def [doco, body] := suite(methBody, indent, ej)
        def span := spanFrom(spanStart)
        return builder.ObjectExpr(doco, name, oAs, oImplements,
            builder.FunctionScript(verb, patts, namedPatts, resultguard, body, span), span)

    def paramDesc(ej):
        def spanStart := spanHere()
        def name := if (considerTag("_", ej)) {
            null
        } else if (peekTag() == "IDENTIFIER") {
            def t := advance(ej)
            _makeStr.fromStr(t[1], t[2])
        } else {
            acceptTag("::", ej)
            acceptTag(".String.", ej)
        }
        def g := if (considerTag(":", ej)) {
            guard(ej)
        } else {
            null
        }
        return builder.ParamDesc(name, g, spanFrom(spanStart))

    def namedParamDesc(ej):
        acceptTag("=>", ej)
        return paramDesc(ej)

    def messageDescInner(indent, tryAgain, ej):
        acceptTag("(", ej)
        def params := acceptList(paramDesc)
        def namedParams := acceptList(namedParamDesc)
        acceptTag(")", ej)
        def resultguard := if (considerTag(":", ej)) {
            if (peekTag() == "EOL") {
                # Oops, end of indenty block.
                position -= 1
                null
            } else {
                guard(ej)
            }
        } else {
            null
        }
        def doco := if ([":", "{"].contains(peekTag())) {
            if (indent) {
                blockLookahead(tryAgain)
            }
            suite(fn _, j {acceptEOLs(); acceptTag(".String.", j)[1]}, indent, ej)
        } else {
            null
        }
        return [doco, params, namedParams, resultguard]

    def messageDesc(indent, ej):
        def spanStart := spanHere()
        acceptTag("to", ej)
        def verb := acceptVerb(ej)
        def [doco, params, namedParams, resultguard] := messageDescInner(indent, ej, ej)
        return builder.MessageDesc(doco, verb, params, namedParams, resultguard, spanFrom(spanStart))

    def interfaceBody(indent, ej):
        def doco := if (peekTag() == ".String.") {
            advance(ej)[1]
        } else {
            null
        }
        def msgs := [].diverge()
        while (true):
            acceptEOLs()
            if (considerTag("pass", ej)):
                continue
            msgs.push(messageDesc(indent, __break))
        catch msg:
            lastError := msg
        return [doco, msgs.snapshot()]

    def basic(indent, tryAgain, ej):
        def origPosition := position
        def tag := peekTag()
        return if (tag == "if"):
            def spanStart := spanHere()
            advance(ej)
            def test := acceptParenExpr(ej)
            if (indent):
                blockLookahead(tryAgain)
            def consq := block(indent, ej)
            def maybeElseStart := position
            if (indent):
                acceptEOLs()
            def alt := if (matchEOLsThenTag(indent, "else")) {
                if (peekTag() == "if") {
                    basic(indent, ej, ej)
                } else {
                    block(indent, ej)
                }} else {
                    position := maybeElseStart
                    null
                }
            builder.IfExpr(test, consq, alt, spanFrom(spanStart))
        else if (tag == "escape"):
            def spanStart := spanHere()
            advance(ej)
            def p1 := pattern(ej)
            if (indent):
                blockLookahead(tryAgain)
            def e1 := block(indent, ej)
            if (matchEOLsThenTag(indent, "catch")):
                def p2 := pattern(ej)
                def e2 := block(indent, ej)
                builder.EscapeExpr(p1, e1, p2, e2, spanFrom(spanStart))
            else:
                builder.EscapeExpr(p1, e1, null, null, spanFrom(spanStart))
        else if (tag == "for"):
            def spanStart := spanHere()
            advance(ej)
            def [k, v, it] := forExprHead(ej)
            if (indent):
                blockLookahead(tryAgain)
            def body := block(indent, ej)
            def [catchPattern, catchBody] := if (matchEOLsThenTag(indent, "catch")) {
                [pattern(ej), block(indent, ej)]
            } else {
                [null, null]
            }
            builder.ForExpr(it, k, v, body, catchPattern, catchBody, spanFrom(spanStart))
        else if (tag == "fn"):
            def spanStart := spanHere()
            advance(ej)
            def patts := acceptList(positionalParam)
            def namedPatts := acceptList(namedParam)
            def body := block(false, ej)
            builder.FunctionExpr(patts, namedPatts, body, spanFrom(spanStart))
        else if (tag == "switch"):
            def spanStart := spanHere()
            advance(ej)
            def spec := acceptParenExpr(ej)
            if (indent):
                blockLookahead(tryAgain)
            builder.SwitchExpr(
                spec,
                suite(fn i, j {repeat(matchers, i, j)}, indent, ej),
                spanFrom(spanStart))
        else if (tag == "try"):
            def spanStart := spanHere()
            advance(ej)
            if (indent):
                blockLookahead(tryAgain)
            def tryblock := block(indent, ej)
            def catchers := [].diverge()
            while (matchEOLsThenTag(indent, "catch")):
                catchers.push(catcher(indent, ej))
            def origPosition := position
            def finallyblock := if (matchEOLsThenTag(indent, "finally")) {
                block(indent, ej)
            } else {
                null
            }
            # make life easier on expander and expander tests
            var n := tryblock
            for [cp, cb] in (catchers):
                n := builder.CatchExpr(n, cp, cb, spanFrom(spanStart))
            if (finallyblock != null):
                n := builder.FinallyExpr(n, finallyblock, spanFrom(spanStart))
            n

        else if (tag == "while"):
            def spanStart := spanHere()
            advance(ej)
            def test := acceptParenExpr(ej)
            if (indent):
                blockLookahead(tryAgain)
            def whileblock := block(indent, ej)
            def catchblock := if (matchEOLsThenTag(indent, "catch")) {
               def spanStart := spanHere()
               def [cp, cb] := catcher(indent, ej)
                builder.Catcher(cp, cb, spanFrom(spanStart))
            } else {
                null
            }
            builder.WhileExpr(test, whileblock, catchblock, spanFrom(spanStart))
        else if (tag == "when"):
            def spanStart := spanHere()
            advance(ej)
            acceptTag("(", ej)
            def exprs := acceptList(expr)
            acceptTag(")", ej)
            acceptTag("->", ej)
            if (indent):
                acceptEOLs()
                acceptTag("INDENT", tryAgain)
            else:
                acceptTag("{", ej)
            acceptEOLs()
            def whenblock := if (!indent && peekTag() == "}") {
                builder.SeqExpr([], null)
            } else {
                seq(indent, fn e {traceln(`sad day! $e`); ej(e)})
            }
            if (indent):
                acceptTag("DEDENT", ej)
            else:
                acceptTag("}", ej)
            def catchers := [].diverge()
            while (matchEOLsThenTag(indent, "catch")):
                def spanStart := spanHere()
                def [cp, cb] := catcher(indent, ej)
                catchers.push(builder.Catcher(cp, cb, spanFrom(spanStart)))
            def finallyblock := if (matchEOLsThenTag(indent, "finally")) {
                block(indent, ej)
            } else {
                null
            }
            builder.WhenExpr(exprs, whenblock, catchers.snapshot(),
                                    finallyblock, spanFrom(spanStart))
        else if (tag == "bind"):
            def spanStart := spanHere()
            advance(ej)
            def n := noun(ej)
            def g := maybeGuard()
            def name := builder.BindPattern(n, g, spanFrom(spanStart))
            switch (peekTag()):
                match ==".":
                    # Custom verb.
                    acceptTag(".", ej)
                    def verb := acceptVerb(ej)
                    objectFunction(name, verb, indent, tryAgain, ej, spanStart)
                match =="(":
                    objectFunction(name, "run", indent, tryAgain, ej, spanStart)
                match ==":=":
                    position := origPosition
                    assign(ej)
                match _:
                    objectExpr(name, indent, tryAgain, ej, spanStart)

        else if (tag == "object"):
            def spanStart := spanHere()
            advance(ej)
            def name := if (considerTag("bind", ej)) {
                def n := noun(ej)
                builder.BindPattern(n, null, spanFrom(spanStart))
            } else if (considerTag("_", ej)) {
                builder.IgnorePattern(null, spanHere())
            } else {
                builder.FinalPattern(noun(ej), null, spanFrom(spanStart))
            }
            objectExpr(name, indent, tryAgain, ej, spanStart)

        else if (tag == "def"):
            def spanStart := spanHere()
            advance(ej)
            var isBind := false
            var verb := "run"
            if (!["IDENTIFIER", "::", "bind", PATTERN_HOLE, VALUE_HOLE].contains(peekTag())):
                position := origPosition
                return assign(ej)
            def name := if (considerTag("bind", ej)) {
                isBind := true
                def n := noun(ej)
                def g := if (considerTag(":", ej)) {
                    guard(ej)
                } else {
                    null
                }
                builder.BindPattern(n, g, spanFrom(spanStart))
            } else {
                builder.FinalPattern(noun(ej), null, spanFrom(spanStart))
            }
            if (considerTag(".", ej)) {
                    verb := acceptVerb(ej)
                    if (peekTag() != "(") {
                        throw.eject(ej, ["expected (", spanNext()])
                    }
                }
            if (peekTag() == "("):
                objectFunction(name, verb, indent, tryAgain, ej, spanStart)
            else if (["exit", ":=", "QUASI_OPEN", "?", ":"].contains(peekTag())):
                position := origPosition
                assign(ej)
            else if (isBind):
                throw.eject(ej, ["expected :=", spanNext()])
            else:
                builder.ForwardExpr(name, spanFrom(spanStart))

        else if (tag == "interface"):
            def spanStart := spanHere()
            advance(ej)
            def name := namePattern(ej, false)
            def guards_ := if (considerTag("guards", ej)) {
                pattern(ej)
            } else {
                null
            }
            def extends_ := if (considerTag("extends", ej)) {
                acceptList(order)
            } else {
                []
            }
            def implements_ := if (considerTag("implements", ej)) {
                acceptList(order)
            } else {
                []
            }
            if (peekTag() == "("):
                def [doco, params, namedParams, resultguard] := messageDescInner(indent, tryAgain, ej)
                builder.FunctionInterfaceExpr(doco, name, guards_, extends_, implements_,
                     builder.MessageDesc(doco, "run", params, namedParams, resultguard, spanFrom(spanStart)),
                     spanFrom(spanStart))
            else:
                if (indent):
                    blockLookahead(tryAgain)
                def [doco, msgs] := suite(interfaceBody, indent, ej)
                builder.InterfaceExpr(doco, name, guards_, extends_, implements_, msgs,
                    spanFrom(spanStart))
        else if (tag == "meta"):
            def spanStart := spanHere()
            acceptTag("meta", ej)
            acceptTag(".", ej)
            def verb := acceptTag("IDENTIFIER", ej)
            if (verb[1] == "context"):
                acceptTag("(", ej)
                acceptTag(")", ej)
                builder.MetaContextExpr(spanFrom(spanStart))
            else if (verb[1] == "getState"):
                acceptTag("(", ej)
                acceptTag(")", ej)
                builder.MetaStateExpr(spanFrom(spanStart))
            else:
                throw.eject(ej, [`Meta verbs are "context" or "getState"`, spanHere()])

        else if (indent && considerTag("pass", ej)):
            builder.SeqExpr([], advance(ej)[2])
        else:
            throw.eject(tryAgain, [`don't recognize $tag`, spanNext()])

    bind blockExpr(ej):
        def origPosition := position
        escape e:
            return basic(true, e, ej)
        position := origPosition
        return expr(ej)

    bind prim(ej):
        def tag := peekTag()
        return if ([".String.", ".int.", ".float64.", ".char."].contains(tag)):
            def t := advance(ej)
            builder.LiteralExpr(t[1], t[2])
        else if (tag == "IDENTIFIER"):
            def t := advance(ej)
            def nex := peekTag()
            if (nex == "QUASI_OPEN" || nex == "QUASI_CLOSE"):
                quasiliteral(t, false, ej)
            else:
                builder.NounExpr(t[1], t[2])
        else if (tag == "&"):
            advance(ej)
            def spanStart := spanHere()
            builder.SlotExpr(noun(ej), spanFrom(spanStart))
        else if (tag == "&&"):
            advance(ej)
            def spanStart := spanHere()
            builder.BindingExpr(noun(ej), spanFrom(spanStart))
        else if (tag == "::"):
            advance(ej)
            def t := acceptTag(".String.", ej)
            builder.NounExpr(t[1], t[2])
        else if (tag == "QUASI_OPEN" || tag == "QUASI_CLOSE"):
            quasiliteral(null, false, ej)
        else if (tag == VALUE_HOLE):
            builder.ValueHoleExpr(advance(ej)[1], spanHere())
        else if (tag == PATTERN_HOLE):
            builder.PatternHoleExpr(advance(ej)[1], spanHere())
        # paren expr
        else if (tag == "("):
            advance(ej)
            acceptEOLs()
            def e := seq(false, ej)
            acceptEOLs()
            acceptTag(")", ej)
            e
        # hideexpr
        else if (tag == "{"):
            def spanStart := spanHere()
            advance(ej)
            acceptEOLs()
            if (considerTag("}", ej)):
                return builder.HideExpr(builder.SeqExpr([], null), spanFrom(spanStart))
            def e := seq(false, ej)
            acceptEOLs()
            acceptTag("}", ej)
            builder.HideExpr(e, spanFrom(spanStart))
        # list/map
        else if (tag == "["):
            def spanStart := spanHere()
            advance(ej)
            acceptEOLs()
            if (considerTag("for", ej)):
                def [k, v, it] := forExprHead(ej)
                def filt := if (considerTag("?", ej)) {
                    acceptParenExpr(ej)
                } else {
                    null
                }
                acceptEOLs()
                def body := expr(ej)
                if (considerTag("=>", ej)):
                    acceptEOLs()
                    def vbody := expr(ej)
                    acceptTag("]", ej)
                    builder.MapComprehensionExpr(it, filt, k, v, body, vbody,
                        spanFrom(spanStart))
                else:
                    acceptTag("]", ej)
                    builder.ListComprehensionExpr(it, filt, k, v, body,
                        spanFrom(spanStart))
            else:
                def [items, isMap] := acceptListOrMap(expr, mapItem)
                acceptEOLs()
                acceptTag("]", ej)
                if (isMap):
                    builder.MapExpr(items, spanFrom(spanStart))
                else:
                    builder.ListExpr(items, spanFrom(spanStart))
        else:
            basic(false, ej, ej)

    def call(ej):
        def spanStart := spanHere()
        def base := prim(ej)
        def trailers := [].diverge()

        # XXX maybe parameterize mapItem instead of doing this
        def unpackMapItems(items):
            var pairs := []
            for node in (items):
                def nn := node.getNodeName()
                if (nn == "MapExprExport"):
                    def sub := node.getValue()
                    def ns := sub.getNodeName()
                    def name := if (ns == "SlotExpr") {
                        builder.LiteralExpr("&" + sub.getNoun().getName(), null)
                    } else if (ns == "BindingExpr") {
                        builder.LiteralExpr("&&" + sub.getNoun().getName(), null)
                    } else {
                        builder.LiteralExpr(sub.getName(), null)
                    }
                    pairs with= ([name, node.getValue()])
                else:
                    pairs with= ([node.getKey(), node.getValue()])
            return pairs

        def positionalArg(ej):
            def origPosition := position
            def v := expr(ej)
            if (peekTag() == "=>"):
                position := origPosition
                throw.eject(ej, null)
            return v

        def callish(methodish, curryish):
            def verb := acceptVerb(ej)
            return if (considerTag("(", ej)):
                def arglist := acceptList(positionalArg)
                def namedArglist := acceptList(namedArg)
                acceptEOLs()
                acceptTag(")", ej)
                trailers.push([methodish, [verb, arglist, namedArglist,
                                           spanFrom(spanStart)]])
                false
            else:
                trailers.push(["CurryExpr", [verb, curryish, spanFrom(spanStart)]])
                true

        def funcallish(name):
            acceptTag("(", ej)
            def arglist := acceptList(positionalArg)
            def namedArglist := acceptList(namedArg)
            acceptEOLs()
            acceptTag(")", ej)
            trailers.push([name, [arglist, namedArglist,
                                  spanFrom(spanStart)]])

        while (true):
            if (considerTag(".", ej)):
                if (callish("MethodCallExpr", false)):
                    break
            else if (peekTag() == "("):
                funcallish("FunCallExpr")
            else if (considerTag("<-", ej)):
                if (peekTag() == "("):
                    funcallish("FunSendExpr")
                else:
                    if(callish("SendExpr", true)):
                        break
            else if (considerTag("[", ej)):
                def arglist := acceptList(expr)
                acceptEOLs()
                acceptTag("]", ej)
                trailers.push(["GetExpr", [arglist, spanFrom(spanStart)]])
            else:
                break
        var result := base
        for tr in (trailers):
            result := M.call(builder, tr[0], [result] + tr[1], [].asMap())
        return result

    def prefix(ej):
        def spanStart := spanHere()
        def op := peekTag()
        return if (op == "-"):
            advance(ej)
            builder.PrefixExpr("-", prim(ej), spanFrom(spanStart))
        else if (["~", "!"].contains(op)):
            advance(ej)
            builder.PrefixExpr(op, call(ej), spanFrom(spanStart))
        else:
            def base := call(ej)
            if (considerTag(":", ej)):
                if (peekTag() == "EOL"):
                    # oops, a token too far
                    position -= 1
                    base
                else:
                    builder.CoerceExpr(base, guard(ej), spanFrom(spanHere()))
            else:
                base
    def operators  := [
        "**" => 1,
        "*" => 2,
        "/" => 2,
        "//" => 2,
        "%" => 2,
        "+" => 3,
        "-" => 3,
        "<<" => 4,
        ">>" => 4,
        ".." => 5,
        "..!" => 5,
        ">" => 6,
        "<" => 6,
        ">=" => 6,
        "<=" => 6,
        "<=>" => 6,
        "=~" => 7,
        "!~" => 7,
        "==" => 7,
        "!=" => 7,
        "&!" => 7,
        "^" => 7,
        "&" => 8,
        "|" => 8,
        "&&" => 9,
        "||" => 10]

    def leftAssociative := ["+", "-", ">>", "<<", "/", "*", "//", "%"]
    def selfAssociative := ["|", "&"]
    def convertInfix(maxPrec, ej):
        def lhs := prefix(ej)
        def output := [lhs].diverge()
        def opstack := [].diverge()
        def emitTop():
            def [_, opName] := opstack.pop()
            def rhs := output.pop()
            def lhs := output.pop()
            def tehSpan := spanCover(lhs.getSpan(), rhs.getSpan())
            if (opName == "=="):
                output.push(builder.SameExpr(lhs, rhs, true, tehSpan))
            else if (opName == "!="):
                output.push(builder.SameExpr(lhs, rhs, false, tehSpan))
            else if (opName == "&&"):
                output.push(builder.AndExpr(lhs, rhs, tehSpan))
            else if (opName == "||"):
                output.push(builder.OrExpr(lhs, rhs, tehSpan))
            else if (["..", "..!"].contains(opName)):
                output.push(builder.RangeExpr(lhs, opName, rhs, tehSpan))
            else if (opName == "=~"):
                output.push(builder.MatchBindExpr(lhs, rhs, tehSpan))
            else if (opName == "!~"):
                output.push(builder.MismatchExpr(lhs, rhs, tehSpan))
            else if ([">", "<", ">=", "<=", "<=>"].contains(opName)):
                output.push(builder.CompareExpr(lhs, opName, rhs, tehSpan))
            else:
                output.push(builder.BinaryExpr(lhs, opName, rhs, tehSpan))

        while (true):
            def op := peekTag()
            def nextPrec := operators.fetch(op, __break)
            if (nextPrec > maxPrec):
                break
            advance(ej)
            acceptEOLs()

            if (opstack.size() > 0):
                def selfy := selfAssociative.contains(op) && (opstack.last()[1] == op)
                def lefty := leftAssociative.contains(op) && opstack.last()[0] <= nextPrec
                def b2 := lefty || selfy
                if (opstack.last()[0] < nextPrec || b2):
                    emitTop()
            opstack.push([operators[op], op])
            if (["=~", "!~"].contains(op)):
                output.push(pattern(ej))
            else:
                output.push(prefix(ej))
        while (opstack.size() > 0):
            emitTop()
        if (output.size() != 1):
            throw(["Internal parser error", spanHere()])
        return output[0]

    bind order(ej):
        return convertInfix(6, ej)

    def infix(ej):
        return convertInfix(10, ej)

    bind comp(ej):
        return convertInfix(8, ej)

    def _assign(ej):
        def spanStart := spanHere()
        def defStart := position
        return if (considerTag("def", ej)):
            def patt := pattern(ej)
            def ex := if (considerTag("exit", ej)) {
                order(ej)
            } else {
                null
            }
            # this might be a ForwardExpr or FunctionScript
            if (peekTag() != ":=" &&
                patt.getNodeName() == "FinalPattern" &&
                ex == null):
                # YEP we should go do that instead
                position := defStart
                basic(false, ej, ej)
            else:
                # Nah it's just a regular def
                acceptTag(":=", ej)
                builder.DefExpr(patt, ex, assign(ej), spanFrom(spanStart))

        # this might be "bind foo(..):" or even "bind foo:"
        else if (["var", "bind"].contains(peekTag())):
            def patt := pattern(ej)
            if ([".", "implements", "as", "extends", "(", "{"].contains(peekTag()) ||
                       ((position + 2 >= tokens.size()) && peekTag() == ":" &&
                        tokens[position + 2][0] == "EOL")):
                position := defStart
                basic(false, ej, ej)
            else:
                acceptTag(":=", ej)
                builder.DefExpr(patt, null, assign(ej), spanFrom(spanStart))

        else:
            def lval := infix(ej)
            if (considerTag(":=", ej)):
                def lt := lval.getNodeName()
                if (["NounExpr", "GetExpr"].contains(lt)):
                    builder.AssignExpr(lval, assign(ej), spanFrom(spanStart))
                else:
                    throw.eject(ej, [`Invalid assignment target $lt`, lt.getSpan()])
            else if (peekTag() =~ `@op=`):
                advance(ej)
                def lt := lval.getNodeName()
                if (["NounExpr", "GetExpr"].contains(lt)):
                    builder.AugAssignExpr(op, lval, assign(ej), spanFrom(spanStart))
                else:
                    throw.eject(ej, [`Invalid assignment target $lt`, lt.getSpan()])
            else if (peekTag() == "VERB_ASSIGN"):
                def verb := advance(ej)[1]
                def lt := lval.getNodeName()
                if (["NounExpr", "GetExpr"].contains(lt)):
                    acceptTag("(", ej)
                    acceptEOLs()
                    def node := builder.VerbAssignExpr(verb, lval, acceptList(expr),
                         spanFrom(spanStart))
                    acceptEOLs()
                    acceptTag(")", ej)
                    node
                else:
                    throw.eject(ej, [`Invalid assignment target $lt`, lt.getSpan()])
            else:
                lval
    bind assign := _assign

    def _expr(ej):
        return if (["continue", "break", "return"].contains(peekTag())):
            def spanStart := spanHere()
            def ex := advanceTag(ej)
            if (peekTag() == "(" && tokens[position + 2][0] == ")"):
                position += 2
                builder.ExitExpr(ex, null, spanFrom(spanStart))
            else if (["EOL", "#", ";", "DEDENT", null].contains(peekTag())):
                builder.ExitExpr(ex, null, spanFrom(spanStart))
            else:
                def val := blockExpr(ej)
                builder.ExitExpr(ex, val, spanFrom(spanStart))
        else:
            assign(ej)

    bind expr := _expr

    def module_(ej):
        def start := spanHere()
        def importsList := [].diverge()
        while (true):
            acceptEOLs()
            acceptTag("import", __break)
            def importName := acceptTag(".String.", ej)[1]
            acceptTag("=~", ej)
            var importPattern := pattern(ej)
            # This might be better placed in the expander, but pre-expansion
            # rewriting of patterns doesn't fit our current bottom-up expansion
            # strategy. Good idea to move it if that changes. ~ A.
            if (importPattern.getNodeName() == "MapPattern" && importPattern.getTail() == null):
                importPattern := builder.MapPattern(
                importPattern.getPatterns(),
                builder.IgnorePattern(null, importPattern.getSpan()),
                importPattern.getSpan())

            importsList.push([importName, importPattern])
            seqSep(ej)
        def exportsList := if (considerTag("exports", ej)) {
            acceptTag("(", ej)
            def nouns := acceptList(noun)
            acceptTag(")", ej)
            seqSep(ej)
            nouns
        } else {
            []
        }
        def body := seq(true, ej)
        return builder."Module"(importsList.snapshot(),
                                exportsList, body,
                                spanFrom(start))

    def start(ej):
        acceptEOLs()
        return if (["import", "exports"].contains(peekTag())):
            module_(ej)
        else:
            seq(true, ej)

    escape e:
        def val := switch (mode) {
            match =="module" {
                start(e)
            }
            match =="expression" {
                seq(true, e)
            }
            match =="pattern" {
                pattern(e)
            }
        }
        acceptEOLs()
        if (position < (tokens.size() - 1)):
            # Ran off the end.
            formatError(lastError, errPartial)
        if (position > (tokens.size() - 1)):
            # Didn't consume enough.
            formatError(lastError, err)
        else:
            return val
    catch p:
        formatError(p, err)


def parseExpression(lex, builder, err, errPartial) as DeepFrozen:
    return parseMonte(lex, builder, "expression", err, errPartial)

def parseModule(lex, builder, err) as DeepFrozen:
    return parseMonte(lex, builder, "module", err, err)

def parsePattern(lex, builder, err) as DeepFrozen:
    return parseMonte(lex, builder, "pattern", err, err)
