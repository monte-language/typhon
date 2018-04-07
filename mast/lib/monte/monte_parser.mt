import "lib/pen" =~ [=> pk, => makeSlicer]
exports (parseModule, parseExpression, parsePattern)

[pk, makeSlicer]

def CONTROL_OPERATORS :DeepFrozen := [
    "catch", "else", "escape", "finally", "fn", "guards",
    "in", "match", "meta",  "try", "IDENTIFIER", "->"].asSet()

def spanCover(left, right) as DeepFrozen:
    return if (left == null) { right } else if (right == null) { left } else {
        left.combine(right)
    }

def tag(t) as DeepFrozen:
    return pk.satisfies(fn [tag, _] { tag == t }) % fn [_, data] { data }

def parseMonte(lex, builder, mode, err, errPartial) as DeepFrozen:
    def [VALUE_HOLE, PATTERN_HOLE] := [lex.valueHole(), lex.patternHole()]

    # Read all the tokens from the lexer.
    def tokens := [].diverge()
    while (true):
        _toks.push(lex.next(__break, errPartial)[1])
    catch p:
        if (p != null):
            throw.eject(err, p)
    def tokens := makeSlicer.fromPairs(_toks.snapshot())

    def eol := (tag("EOL") / tag("#")).zeroOrMore()

    def ident := tag("IDENTIFIER")
    def plainnoun := ident % fn n, => span { builder.NounExpr(n, span) }
    def shamenoun := tag("::") >> tag(".String.") % fn n, => span {
        builder.NounExpr(n, span)
    }
    def noun := plainnoun / shamenoun
    def valuehole := tag(VALUE_HOLE) % fn i, => span {
        builder.ValueHoleExpr(i, span)
    }
    def patternhole := tag(PATTERN_HOLE) % fn i, => span {
        builder.PatternHoleExpr(i, span)
    }
    def nounlike := noun / valuehole / patternhole

    def literal := (tag(".String.") / tag(".int.") / tag(".float64.") /
                    tag(".char.")) % fn d, => span {
        builder.LiteralExpr(d, span)
    }

    # Forward-declared really early in order to be usable in combinators.
    def expr

    def parens(parser):
        return tag("(") >> eol >> parser << eol << tag(")")
    def brackets(parser):
        return tag("[") >> eol >> parser << eol << tag("]")

    def parenexpr := parens(expr)

    def indentTag(t):
        return eol >> tag(t)

    def verb := tag(".String.") / ident

    def listOf(parser):
        return parser.joinedBy(tag(",") >> eol)

    def order
    def comp
    def blockExpr
    def prim
    def pattern
    def assign

    def quasiopen := tag("QUASI_OPEN") % fn data, => span {
        if (data != null) { builder.QuasiText(data, span) }
    }
    def quasiclose := tag("QUASI_CLOSE") % fn data, => span {
        builder.QuasiText(data, span)
    }
    def exprhole := (tag("DOLLAR_IDENT") % fn noun, => span {
        builder.QuasiExprHole(builder.NounExpr(noun, span), span)
    }) / (expr.bracket(tag("${"), tag("}")) % fn ex {
        builder.QuasiExprHole(ex, ex.getSpan())
    })
    def patthole := (tag("AT_IDENT") % fn noun, => span {
        def patt := if (noun == "_") {
            builder.IgnorePattern(null, span)
        } else {
            builder.FinalPattern(builder.NounExpr(noun, span), null, span)
        }
        builder.QuasiPatternHole(patt, span)
    }) / (pattern.bracket(tag("@{"), tag("}")) % fn patt {
        builder.QuasiPatternHole(patt, patt.getSpan())
    })

    def quasiexpr := (ident.optional() +
        (quasiopen / exprhole).zeroOrMore() +
        quasiclose) % fn [[id, parts], close] {
        builder.QuasiParserExpr(id, parts.with(close), close.getSpan())
    }

    def quasipatt := (ident.optional() +
        (quasiopen / exprhole / patthole).zeroOrMore() +
        quasiclose) % fn [[id, parts], close] {
        builder.QuasiParserPattern(id, parts.with(close), close.getSpan())
    }

    def guardget := (noun + brackets(listOf(expr)).optional()) % fn [n, subs], => span {
        builder.GetExpr(n, subs, span)
    }
    def guard := tag(":") >> (guardget / parenexpr)
    def nounguard := noun + guard.optional()

    def finalpatt := nounguard % fn [n, g], => span {
        builder.FinalPattern(n, g, span)
    }
    def varpatt := tag("var") >> nounguard % fn [n, g], => span {
        builder.VarPattern(n, g, span)
    }
    def slotpatt := tag("&") >> nounguard % fn [n, g], => span {
        builder.SlotPattern(n, g, span)
    }
    def bindingpatt := tag("&&") >> noun % fn n, => span {
        builder.BindingPattern(n, span)
    }
    def bindpatt := tag("bind") >> nounguard % fn [n, g], => span {
        builder.BindPattern(n, g, span)
    }
    def valueholepatt := tag(VALUE_HOLE) % fn i, => span {
        builder.ValueHolePattern(i, span)
    }
    def patternholepatt := tag(PATTERN_HOLE) % fn i, => span {
        builder.PatternHolePattern(i, span)
    }

    def namepatt := (finalpatt / varpatt / slotpatt / bindingpatt /
                     valueholepatt / patternholepatt)

    def paramitem(buildPair, buildImport):
        def imp := ((tag("=>") >> namepatt) +
                (tag(":=") >> order).optional()) % fn [np, d], => span {
            buildImport(np, d, span)
        }
        def key := (parenexpr / literal) << tag("=>")
        def default := (tag(":=") >> order).optional()
        def pair := (key + pattern + default) % fn [[k, p], d], => span {
            buildPair(k, p, d, span)
        }
        return imp / pair
    def mappattitem := paramitem(builder.MapPatternAssoc,
                                 builder.MapPatternImport)
    def namedparam := paramitem(builder.NamedParam, builder.NamedParamImport)

    def samepatt := tag("==") >> prim % fn p, => span {
        builder.SamePattern(p, true, span)
    }
    def notsamepatt := tag("!=") >> prim % fn p, => span {
        builder.SamePattern(p, false, span)
    }
    def ignorepatt := tag("_") >> guard.optional() % fn g, => span {
        builder.IgnorePattern(g, span)
    }
    def viapatt := tag("via") >> (parenexpr + pattern) % fn [e, p], => span {
        builder.ViaPattern(e, p, span)
    }
    def listpatt := (brackets(listOf(pattern).optional()) +
                     (tag("|") >> pattern).optional()) % fn [ps, t], => span {
        builder.ListPattern(ps, t, span)
    }
    def mappatt := (brackets(listOf(mappattitem).optional()) +
                     (tag("+") >> pattern).optional()) % fn [ps, t], => span {
        builder.MapPattern(ps, t, span)
    }
    def patt := (quasipatt / namepatt / samepatt / notsamepatt / viapatt /
                 bindpatt / ignorepatt / listpatt / mappatt)
    bind pattern := (patt + (tag("?") >> parenexpr).optional()) % fn [p, e], => span {
        if (e != null) { builder.SuchThatPattern(p, e, span) } else { p }
    }

    def pairitem(makeExport, makePair):
        def slot := tag("&") >> noun % fn n, => span {
            builder.SlotExpr(n, span)
        }
        def binding := tag("&&") >> noun % fn n, => span {
            builder.BindingExpr(n, span)
        }
        def export := tag("=>") >> (slot / binding / noun) % fn expr, => span {
            makeExport(expr, span)
        }
        def pair := (expr + (tag("=>") >> expr)) % fn [k, v], => span {
            makePair(k, v, span)
        }
        return export / pair
    def mapitem := pairitem(builder.MapExprExport, builder.MapExprAssoc)
    def namedarg := pairitem(builder.NamedArgExport, builder.NamedArg)

    # Quirky name: This is the separator between items in a SeqExpr.
    def seqsep := (tag(";") / tag("#") / tag("EOL")).oneOrMore()

    def seqReduce(exprs, => span):
        return if (exprs =~ [e]) { e } else { builder.SeqExpr(exprs, span) }
    def blockseq := blockexpr.joinedBy(seqsep) % seqReduce
    def seq := expr.joinedBy(seqsep) % seqReduce

    # XXX not handling `pass` because it is stupid
    def indentblock := blockseq.bracket(tag(":") >> eol >> tag("INDENT") >> eol,
                                        tag("DEDENT"))
    def block := seq.bracket(tag("{") >> eol, tag("}"))

    # XXX

    def indentsuite(parser):
        return parser.bracket(tag(":") >> eol >> tag("INDENT") >> eol,
                              eol >> tag("DEDENT"))
    def suite(parser):
        return parser.bracket(tag("{") >> eol, eol >> tag("}"))

    def _in := eol >> tag("in") << eol
    def _forexpr := tag("(") >> eol >> comp << eol << tag(")")
    def _forpatts := (pattern << tag("=>")).optional() + pattern
    def forexprhead := _forpatts + (_in >> _forexpr)

    def indentmatcher := ((tag("match") >> pattern) + (indentblock << eol)) % fn [pp, bl], => span {
        builder.Matcher(pp, bl, span)
    }
    def matcher := ((tag("match") >> pattern) + (block << eol)) % fn [pp, bl], => span {
        builder.Matcher(pp, bl, span)
    }

    def indentcatcher := pattern + indentblock
    def catcher := pattern + block

    # XXX

    def methBody(indent, ej):
        acceptEOLs()
        def [_, doco, docoSpan] := if (peekTag() == ".String.") {
            advance(ej)
        } else {
            [null, null, null]
        }
        acceptEOLs()
        return if ((!indent && peekTag() == "}") ||
                   (indent && peekTag() == "DEDENT" && doco != null)):
            [doco, builder.SeqExpr(
                if (doco == null) {[]
                } else {[builder.LiteralExpr(doco, docoSpan)]}, spanHere())]
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
                # XXX note from the past: repeat() is just .zeroOrMore() with
                # indent passed through. ~ C.
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
                builder.SeqExpr([], spanHere())
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
                return builder.HideExpr(builder.SeqExpr([], spanHere()), spanFrom(spanStart))
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
                # this can go two ways, and we're going to be optimistic about
                # the first one
                funcallish("FunCallExpr")
                if (CONTROL_OPERATORS.contains(peekTag())):
                    def o := advance(ej)
                    def operator := if (o[0] == "IDENTIFIER") {
                        _makeStr.fromStr(o[1], o[2])
                    } else {
                        o[0]
                    }
                    def [_, [args, namedArgs, _]] := trailers.pop()
                    if (namedArgs.size() > 0):
                        throw.eject(ej, ["Control blocks don't take named args",
                                         namedArgs[0].getSpan()])
                    def params := acceptList(pattern)
                    trailers.push(["ControlExpr",
                                   [operator, args, params, block(false, ej), false,
                                    spanFrom(spanStart)]])
                    # Assume that we have many more control-exprs to parse.
                    # We'll break when done.
                    while (true):
                        # If there are arguments, then they must be
                        # parenthesized. Zero-argument empty parens are legal.
                        # Otherwise, we need a control word. If we peek and
                        # find neither, then we aren't parsing a control-expr.
                        if (!CONTROL_OPERATORS.with("(").contains(peekTag())):
                            break
                        def args := if (considerTag("(", ej)) {
                            def es := acceptList(expr)
                            acceptTag(")", ej)
                            es
                        } else { [] }
                        if (!CONTROL_OPERATORS.contains(peekTag())):
                            formatError(null, ej)
                        def o := advance(ej)
                        def operator := if (o[0] == "IDENTIFIER") {
                            _makeStr.fromStr(o[1], o[2])
                        } else {
                            o[0]
                        }
                        def params := if (peekTag() == "{") { [] } else {
                            acceptList(pattern)
                        }
                        trailers.push(["ControlExpr",
                                       [operator, args, params, block(false, ej), false,
                                        spanFrom(spanStart)]])
                    trailers.push(["ControlExpr", trailers.pop()[1].with(4, true)])
                    break
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
                peekTag() != ":" &&
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
            # Called like `continue()` or `break()`
            if (peekTag() == "(" && tokens[position + 2][0] == ")"):
                position += 2
                builder.ExitExpr(ex, null, spanFrom(spanStart))
            # Is there an expression coming up? Peek to make an educated
            # guess. If no, then act like `break null`; otherwise, parse an
            # expression.
            else if (["}", "EOL", "#", ";", "DEDENT", null].contains(peekTag())):
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
            def importStart := spanHere()
            def importName := acceptTag(".String.", ej)[1]
            acceptTag("=~", ej)
            def importPattern := pattern(ej)
            importsList.push(builder."Import"(importName, importPattern,
                                              spanFrom(importStart)))
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
                # Make life better for m`` users. Methods and matchers start
                # with keywords, so we can unambiguously start with them. ~ C.
                switch (peekTag()) {
                    match =="method" { meth(false, e) }
                    match =="to" { meth(false, e) }
                    match =="match" { matchers(false, e) }
                    match _ { seq(true, e) }
                }
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
