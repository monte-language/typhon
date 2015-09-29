def spanCover(left, right) as DeepFrozen:
    if (left == null || right == null):
        return null
    return left.combine(right)

def parseMonte(lex, builder, mode, err) as DeepFrozen:
    def [VALUE_HOLE, PATTERN_HOLE] := [lex.valueHole(), lex.patternHole()]
    def _toks := [].diverge()
    while (true):
         _toks.push(lex.next(__break)[1])
    catch p:
        if (p != null):
            throw.eject(err, p)
    def tokens := _toks.snapshot()
    var dollarHoleValueIndex := -1
    var atHoleValueIndex := -1
    var position := -1
    var lastError := null

    def formatError(var error, err):
        if (error == null):
            error := ["Syntax error", tokens[position][2]]
        if (error =~ [errMsg, span]):
            if (span == null):
                # There's no span information. This is legal and caused by
                # token exhaustion.
                throw.eject(err, "Error at end of input: " + errMsg)

            def front := (span.getStartLine() - 3).max(0)
            def back := span.getEndLine() + 3
            def lines := lex.getInput().split("\n").slice(front, back)
            def msg := [].diverge()
            var i := front
            for line in lines:
                i += 1
                def lnum := M.toString(i)
                def pad := " " * (4 - lnum.size())
                msg.push(`$pad$lnum $line`)
                if (i == span.getStartLine()):
                    def errLine := "    " + " " * span.getStartCol() + "^"
                    if (span.getStartLine() == span.getEndLine()):
                        msg.push(errLine + "~" * (span.getEndCol() - span.getStartCol()))
                    else:
                        msg.push(errLine)
            msg.push(errMsg)
            def msglines := msg.snapshot()
            def fullMsg := "\n".join(msglines) + "\n"
            throw.eject(err, fullMsg)
        else:
            throw.eject(err, `what am I supposed to do with $error ?`)

    def giveUp(e):
        formatError(e, err)

    def spanHere():
        if (position + 1 >= tokens.size()):
            return null
        return tokens[position.max(0)][2]

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
            throw.eject(fail, [`expected $tagname, got $specname`, spanHere()])
        return t

    def acceptEOLs():
        while (true):
            if ((position + 1) >= tokens.size()):
                return
            def t := tokens[position + 1]
            if (!["EOL", "#"].contains(t[0])):
                return
            position += 1

    def peek():
        if (position + 1 >= tokens.size()):
            return null
        return tokens[position + 1]

    def opt(rule, ej):
        escape e:
            return rule(e)
        catch _:
            return null

    def peekTag():
        if (position + 1 >= tokens.size()):
            return null
        def t := tokens[position + 1]
        return t[0]

    def matchEOLsThenTag(indent, tagname):
        def origPosition := position
        if (indent):
            acceptEOLs()
        if (position + 1 >= tokens.size()):
            position := origPosition
            return false
        if (tokens[position + 1][0] == tagname):
            position += 1
            return true
        else:
            position := origPosition
            return false

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

    def expr
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
        if (isPattern):
            return builder.QuasiParserPattern(name, parts.snapshot(), spanFrom(spanStart))
        else:
            return builder.QuasiParserExpr(name, parts.snapshot(), spanFrom(spanStart))

    def guard(ej):
       def spanStart := spanHere()
       if (peekTag() == "IDENTIFIER"):
            def t := advance(ej)
            def n := builder.NounExpr(t[1], t[2])
            if (peekTag() == "["):
                advance(ej)
                def g := acceptList(expr)
                acceptTag("]", ej)
                return builder.GetExpr(n, g, spanFrom(spanStart))
            else:
                return n
       acceptTag("(", ej)
       def e := expr(ej)
       acceptTag(")", ej)
       return e

    def noun(ej):
        if (peekTag() == VALUE_HOLE):
            return builder.ValueHoleExpr(advance(ej)[1], spanHere())
        if (peekTag() == PATTERN_HOLE):
            return builder.PatternHoleExpr(advance(ej)[1], spanHere())
        if (peekTag() == "IDENTIFIER"):
            def t := advance(ej)
            return builder.NounExpr(t[1], t[2])
        else:
            def spanStart := spanHere()
            acceptTag("::", ej)
            def t := acceptTag(".String.", ej)
            return builder.NounExpr(t[1], spanFrom(spanStart))

    def maybeGuard():
        def origPosition := position
        if (peekTag() == ":"):
            advance(null)
            escape e:
                return guard(e)
            catch _:
                # might be suite-starting colon
                position := origPosition
                return null

    def namePattern(ej, tryQuasi):
        def spanStart := spanHere()
        def nex := peekTag()
        if (nex == "IDENTIFIER"):
            def t := advance(ej)
            def nex2 := peekTag()
            if (nex2 == "QUASI_OPEN" || nex2 == "QUASI_CLOSE"):
                if (tryQuasi):
                    return quasiliteral(t, true, ej)
                else:
                    throw.eject(ej, [nex2, spanHere()])
            else:
                def g := maybeGuard()
                return builder.FinalPattern(builder.NounExpr(t[1], t[2]), g, spanFrom(spanStart))
        else if (nex == "::"):
            advance(ej)
            def spanStart := spanHere()
            def t := acceptTag(".String.", ej)
            def g := maybeGuard()
            return builder.FinalPattern(builder.NounExpr(t[1], t[2]), g, spanFrom(spanStart))
        else if (nex == "var"):
            advance(ej)
            def n := noun(ej)
            def g := maybeGuard()
            return builder.VarPattern(n, g, spanFrom(spanStart))
        else if (nex == "&"):
            advance(ej)
            def n := noun(ej)
            def g := maybeGuard()
            return builder.SlotPattern(n, g, spanFrom(spanStart))
        else if (nex == "&&"):
            advance(ej)
            return builder.BindingPattern(noun(ej), spanFrom(spanStart))
        else if (nex == "bind"):
            advance(ej)
            def n := noun(ej)
            def g := maybeGuard()
            return builder.BindPattern(n, g, spanFrom(spanStart))
        else if (nex == VALUE_HOLE):
            return builder.ValueHolePattern(advance(ej)[1], spanHere())
        else if (nex == PATTERN_HOLE):
            return builder.PatternHolePattern(advance(ej)[1], spanHere())
        throw.eject(ej, [`Unrecognized name pattern $nex`, spanHere()])

    def mapPatternItemInner(ej):
        def spanStart := spanHere()
        if (peekTag() == "=>"):
            advance(ej)
            def p := namePattern(ej, false)
            return builder.MapPatternImport(p, spanFrom(spanStart))
        def k := if (peekTag() == "(") {
            advance(ej)
            def e := expr(ej)
            acceptEOLs()
            acceptTag(")", ej)
            e
        } else {
            if ([".String.", ".int.", ".float64.", ".char."].contains(peekTag())) {
                def t := advance(ej)
                builder.LiteralExpr(t[1], t[2])
            } else {
                throw.eject(ej, ["Map pattern keys must be literals or expressions in parens", spanHere()])
            }
        }
        acceptTag("=>", ej)
        return builder.MapPatternAssoc(k, pattern(ej), spanFrom(spanStart))

    def mapPatternItem(ej):
        def spanStart := spanHere()
        def p := mapPatternItemInner(ej)
        if (peekTag() == ":="):
            advance(ej)
            return builder.MapPatternDefault(p, order(ej), spanFrom(spanStart))
        else:
            return builder.MapPatternRequired(p, spanFrom(spanStart))

    def _pattern(ej):
        escape e:
            return namePattern(e, true)
        # ... if namePattern fails, keep going
        def spanStart := spanHere()
        def nex := peekTag()
        if (nex == "QUASI_OPEN" || nex == "QUASI_CLOSE"):
            return quasiliteral(null, true, ej)
        else if (nex == "=="):
            def spanStart := spanHere()
            advance(ej)
            return builder.SamePattern(prim(ej), true, spanFrom(spanStart))
        else if (nex == "!="):
            def spanStart := spanHere()
            advance(ej)
            return builder.SamePattern(prim(ej), false, spanFrom(spanStart))
        else if (nex == "_"):
            advance(ej)
            def spanStart := spanHere()
            def g := if (peekTag() == ":" && tokens[position + 2][0] != "EOL") {
                advance(ej); guard(ej)
            } else {
                null
            }
            return builder.IgnorePattern(g, spanFrom(spanStart))
        else if (nex == "via"):
            advance(ej)
            def spanStart := spanHere()
            acceptTag("(", ej)
            def e := expr(ej)
            acceptTag(")", ej)
            return builder.ViaPattern(e, pattern(ej), spanFrom(spanStart))
        else if (nex == "["):
            def spanStart := spanHere()
            advance(ej)
            def [items, isMap] := acceptListOrMap(pattern, mapPatternItem)
            acceptEOLs()
            acceptTag("]", ej)
            if (isMap):
                def tail := if (peekTag() == "|") {advance(ej); _pattern(ej)}
                return builder.MapPattern(items, tail, spanFrom(spanStart))
            else:
                def tail := if (peekTag() == "+") {advance(ej); _pattern(ej)}
                return builder.ListPattern(items, tail, spanFrom(spanStart))
        else if (nex == VALUE_HOLE):
            return builder.ValueHolePattern(advance(ej)[1], spanHere())
        else if (nex == PATTERN_HOLE):
            return builder.PatternHolePattern(advance(ej)[1], spanHere())
        throw.eject(ej, [`Invalid pattern $nex`, spanHere()])

    bind pattern(ej):
        def spanStart := spanHere()
        def p := _pattern(ej)
        if (peekTag() == "?"):
            advance(ej)
            acceptTag("(", ej)
            def e := expr(ej)
            acceptTag(")", ej)
            return builder.SuchThatPattern(p, e, spanFrom(spanStart))
        else:
            return p
    "XXX buggy expander eats this line"

    def mapItem(ej):
        def spanStart := spanHere()
        if (peekTag() == "=>"):
            advance(ej)
            if (peekTag() == "&"):
                advance(ej)
                return builder.MapExprExport(builder.SlotExpr(noun(ej), spanFrom(spanStart)), spanFrom(spanStart))
            else if (peekTag() == "&&"):
                advance(ej)
                return builder.MapExprExport(builder.BindingExpr(noun(ej), spanFrom(spanStart)), spanFrom(spanStart))
            else:
                return builder.MapExprExport(noun(ej), spanFrom(spanStart))
        def k := expr(ej)
        acceptTag("=>", ej)
        def v := expr(ej)
        return builder.MapExprAssoc(k, v, spanFrom(spanStart))

    def seqSep(ej):
        if (![";", "#", "EOL"].contains(peekTag())):
            ej(["Expected a semicolon or newline after expression", tokens[position][2]])
        advance(ej)
        while (true):
            if (![";", "#", "EOL"].contains(peekTag())):
                break
            advance(ej)

    def seq(indent, ej):
        def ex := if (indent) {blockExpr} else {expr}
        def start := spanHere()
        def exprs := [ex(ej)].diverge()
        while (true):
            seqSep(__break)
            exprs.push(ex(__break))
        catch msg:
            lastError := msg
        opt(seqSep, ej)
        if (exprs.size() == 1):
            return exprs[0]
        return builder.SeqExpr(exprs.snapshot(), spanFrom(start))

    def block(indent, ej):
        if (indent):
            acceptTag(":", ej)
            acceptEOLs()
            acceptTag("INDENT", ej)
        else:
            acceptTag("{", ej)
        acceptEOLs()
        def contents := if (peekTag() == "pass") {
            advance(ej)
            acceptEOLs()
            builder.SeqExpr([], null)
        } else {
            escape e {
                seq(indent, ej)
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

    def repeat(rule, indent, ej):
        def contents := [].diverge()
        while (true):
            contents.push(rule(indent, __break))
        catch msg:
            lastError := msg
        return contents.snapshot()

    def forExprHead(needParens, ej):
        def p1 := pattern(ej)
        def p2 := if (peekTag() == "=>") {advance(ej); pattern(ej)
                  } else {null}
        if (needParens):
            acceptEOLs()
        acceptTag("in", ej)
        if (needParens):
            acceptEOLs()
            acceptTag("(", ej)
            acceptEOLs()
        def it := comp(ej)
        if (needParens):
            acceptEOLs()
            acceptTag(")", ej)
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
        def spanStart := spanHere()
        return builder.Catcher(pattern(ej), block(indent, ej), spanFrom(spanStart))

    def methBody(indent, ej):
        acceptEOLs()
        def doco := if (peekTag() == ".String.") {
            advance(ej)[1]
        } else {
            null
        }
        acceptEOLs()
        def contents := escape e {
            seq(indent, ej)
        } catch _ {
            builder.SeqExpr([], null)
        }
        return [doco, contents]

    def positionalParam(ej):
        def pattStart := position
        def p := pattern(ej)
        if (peekTag() == "=>"):
            position := pattStart
            throw.eject(ej, null)
        return p

    def namedParam(ej):
        # XXX consider parameterizing mapPatternItem instead of
        # destructuring like this.
        def node := mapPatternItem(ej)
        def [mapPatt, default] := [node.getKeyer(), node.getDefault()]
        def nn := mapPatt.getNodeName()
        def [k, p] := if (nn == "MapPatternImport") {
            def sub := mapPatt.getPattern()
            def ns := sub.getNodeName()
            def name := if (ns == "SlotPattern") {
                [builder.LiteralExpr("&" + sub.getNoun().getName(), null), sub]
            } else if (ns == "BindingPattern") {
                [builder.LiteralExpr("&&" + sub.getNoun().getName(), null), sub]
            } else {
                [builder.LiteralExpr(sub.getNoun().getName(), null), sub]
            }
        } else {
            [mapPatt.getKey(), mapPatt.getValue()]
        }
        return builder.NamedParam(k, p, default, node.getSpan())

    def meth(indent, ej):
        acceptEOLs()
        def spanStart := spanHere()
        def mknode := if (peekTag() == "to") {
            advance(ej)
            builder."To"
        } else {
            acceptTag("method", ej)
            builder."Method"
        }
        def verb := if (peekTag() == ".String.") {
            advance(ej)[1]
        } else {
            def t := acceptTag("IDENTIFIER", ej)
            __makeString.fromString(t[1], t[2])
        }
        acceptTag("(", ej)
        def patts := acceptList(positionalParam)
        def namedPatts := acceptList(namedParam)
        acceptTag(")", ej)
        def resultguard := if (peekTag() == ":") {
            advance(ej)
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
            if (peekTag() == "pass"):
                advance(ej)
                continue
            meths.push(meth(indent, __break))
        catch msg:
            lastError := msg
        def matchs := [].diverge()
        while (true):
            if (peekTag() == "pass"):
                advance(ej)
                continue
            matchs.push(matchers(indent, __break))
        catch msg:
            lastError := msg
        return [doco, meths.snapshot(), matchs.snapshot()]

    def oAuditors(ej):
        return [
            if (peekTag() == "as") {
                advance(ej)
                order(ej)
            } else {
                null
            },
            if (peekTag() == "implements") {
                advance(ej)
                acceptList(order)
            } else {
                []
            }]

    def blockLookahead(ej):
        def origPosition := position
        try:
            acceptTag(":", ej)
            acceptEOLs()
            acceptTag("INDENT", ej)
        finally:
            position := origPosition

    def objectExpr(name, indent, tryAgain, ej, spanStart):
        def oExtends := if (peekTag() == "extends") {
            advance(ej)
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

    def objectFunction(name, indent, tryAgain, ej, spanStart):
        acceptTag("(", ej)
        def patts := acceptList(positionalParam)
        def namedPatts := acceptList(namedParam)
        acceptTag(")", ej)
        def resultguard := if (peekTag() == ":") {
            advance(ej)
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
            builder.FunctionScript(patts, namedPatts, resultguard, body, span), span)

    def paramDesc(ej):
        def spanStart := spanHere()
        def name := if (peekTag() == "_") {
            advance(ej)
            null
        } else if (peekTag() == "IDENTIFIER") {
            def t := advance(ej)
            __makeString.fromString(t[1], t[2])
        } else {
            acceptTag("::", ej)
            acceptTag(".String.", ej)
        }
        def g := if (peekTag() == ":") {
            advance(ej)
            guard(ej)
        } else {
            null
        }
        return builder.ParamDesc(name, g, spanFrom(spanStart))

    def messageDescInner(indent, tryAgain, ej):
        acceptTag("(", ej)
        def params := acceptList(paramDesc)
        acceptTag(")", ej)
        def resultguard := if (peekTag() == ":") {
            advance(ej)
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
            suite(fn i, j {acceptEOLs(); acceptTag(".String.", j)[1]}, indent, ej)
        } else {
            null
        }
        return [doco, params, resultguard]

    def messageDesc(indent, ej):
        def spanStart := spanHere()
        acceptTag("to", ej)
        def verb := if (peekTag() == ".String.") {
            advance(ej)
        } else {
            def t := acceptTag("IDENTIFIER", ej)
            __makeString.fromString(t[1], t[2])
        }
        def [doco, params, resultguard] := messageDescInner(indent, ej, ej)
        return builder.MessageDesc(doco, verb, params, resultguard, spanFrom(spanStart))

    def interfaceBody(indent, ej):
        def doco := if (peekTag() == ".String.") {
            advance(ej)[1]
        } else {
            null
        }
        def msgs := [].diverge()
        while (true):
            acceptEOLs()
            if (peekTag() == "pass"):
                advance(ej)
                continue
            msgs.push(messageDesc(indent, __break))
        catch msg:
            lastError := msg
        return [doco, msgs.snapshot()]

    def basic(indent, tryAgain, ej):
        def origPosition := position
        def tag := peekTag()
        if (tag == "if"):
            def spanStart := spanHere()
            advance(ej)
            acceptTag("(", giveUp)
            def test := expr(ej)
            acceptTag(")", giveUp)
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
            return builder.IfExpr(test, consq, alt, spanFrom(spanStart))
        if (tag == "escape"):
            def spanStart := spanHere()
            advance(ej)
            def p1 := pattern(ej)
            if (indent):
                blockLookahead(tryAgain)
            def e1 := block(indent, ej)
            if (matchEOLsThenTag(indent, "catch")):
                def p2 := pattern(ej)
                def e2 := block(indent, ej)
                return builder.EscapeExpr(p1, e1, p2, e2, spanFrom(spanStart))
            return builder.EscapeExpr(p1, e1, null, null, spanFrom(spanStart))
        if (tag == "for"):
            def spanStart := spanHere()
            advance(ej)
            def [k, v, it] := forExprHead(false, ej)
            if (indent):
                blockLookahead(tryAgain)
            def body := block(indent, ej)
            def [catchPattern, catchBody] := if (matchEOLsThenTag(indent, "catch")) {
                [pattern(ej), block(indent, ej)]
            } else {
                [null, null]
            }
            return builder.ForExpr(it, k, v, body, catchPattern, catchBody, spanFrom(spanStart))
        if (tag == "fn"):
            def spanStart := spanHere()
            advance(ej)
            def patt := acceptList(pattern)
            def body := block(false, ej)
            return builder.FunctionExpr(patt, body, spanFrom(spanStart))
        if (tag == "switch"):
            def spanStart := spanHere()
            advance(ej)
            acceptTag("(", ej)
            def spec := expr(ej)
            acceptTag(")", ej)
            if (indent):
                blockLookahead(tryAgain)
            return builder.SwitchExpr(
                spec,
                suite(fn i, j {repeat(matchers, i, j)}, indent, ej),
                spanFrom(spanStart))
        if (tag == "try"):
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
            return builder.TryExpr(tryblock, catchers.snapshot(),
                                   finallyblock, spanFrom(spanStart))
        if (tag == "while"):
            def spanStart := spanHere()
            advance(ej)
            acceptTag("(", ej)
            def test := expr(ej)
            acceptTag(")", ej)
            if (indent):
                blockLookahead(tryAgain)
            def whileblock := block(indent, ej)
            def catchblock := if (matchEOLsThenTag(indent, "catch")) {
               catcher(indent, ej)
            } else {
                null
            }
            return builder.WhileExpr(test, whileblock, catchblock, spanFrom(spanStart))
        if (tag == "when"):
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
            def whenblock := escape e {
                seq(indent, ej)
            } catch _ {
                builder.SeqExpr([], null)
            }
            if (indent):
                acceptTag("DEDENT", ej)
            else:
                acceptTag("}", ej)
            def catchers := [].diverge()
            while (matchEOLsThenTag(indent, "catch")):
               catchers.push(catcher(indent, ej))
            def finallyblock := if (matchEOLsThenTag(indent, "finally")) {
                block(indent, ej)
            } else {
                null
            }
            return builder.WhenExpr(exprs, whenblock, catchers.snapshot(),
                                    finallyblock, spanFrom(spanStart))
        if (tag == "bind"):
            def spanStart := spanHere()
            advance(ej)
            def n := noun(ej)
            def g := maybeGuard()
            def name := builder.BindPattern(n, g, spanFrom(spanStart))
            if (peekTag() == "("):
                return objectFunction(name, indent, tryAgain, ej, spanStart)
            else if (peekTag() == ":="):
                position := origPosition
                return assign(ej)
            else:
                return objectExpr(name, indent, tryAgain, ej, spanStart)

        if (tag == "object"):
            def spanStart := spanHere()
            advance(ej)
            def name := if (peekTag() == "bind") {
                advance(ej)
                def n := noun(ej)
                builder.BindPattern(n, null, spanFrom(spanStart))
            } else if (peekTag() == "_") {
                advance(ej)
                builder.IgnorePattern(null, spanHere())
            } else {
                builder.FinalPattern(noun(ej), null, spanFrom(spanStart))
            }
            return objectExpr(name, indent, tryAgain, ej, spanStart)

        if (tag == "def"):
            def spanStart := spanHere()
            advance(ej)
            var isBind := false
            if (!["IDENTIFIER", "::", "bind", PATTERN_HOLE, VALUE_HOLE].contains(peekTag())):
                position := origPosition
                return assign(ej)
            def name := if (peekTag() == "bind") {
                advance(ej)
                isBind := true
                def n := noun(ej)
                def g := if (peekTag() == ":") {
                    advance(ej)
                    guard(ej)
                } else {
                    null
                }
                builder.BindPattern(n, g, spanFrom(spanStart))
            } else {
                builder.FinalPattern(noun(ej), null, spanFrom(spanStart))
            }
            if (peekTag() == "("):
                return objectFunction(name, indent, tryAgain, ej, spanStart)
            else if (["exit", ":=", "QUASI_OPEN", "?", ":"].contains(peekTag())):
                position := origPosition
                return assign(ej)
            else if (isBind):
                throw.eject(ej, ["expected :=", spanHere()])
            else:
                return builder.ForwardExpr(name, spanFrom(spanStart))

        if (tag == "interface"):
            def spanStart := spanHere()
            advance(ej)
            def name := namePattern(ej, false)
            def guards_ := if (peekTag() == "guards") {
                advance(ej)
                pattern(ej)
            } else {
                null
            }
            def extends_ := if (peekTag() == "extends") {
                advance(ej)
                acceptList(order)
            } else {
                []
            }
            def implements_ := if (peekTag() == "implements") {
                advance(ej)
                acceptList(order)
            } else {
                []
            }
            if (peekTag() == "("):
                def [doco, params, resultguard] := messageDescInner(indent, tryAgain, ej)
                return builder.FunctionInterfaceExpr(doco, name, guards_, extends_, implements_,
                     builder.MessageDesc(doco, "run", params, resultguard, spanFrom(spanStart)),
                     spanFrom(spanStart))
            if (indent):
                blockLookahead(tryAgain)
            def [doco, msgs] := suite(interfaceBody, indent, ej)
            return builder.InterfaceExpr(doco, name, guards_, extends_, implements_, msgs,
                spanFrom(spanStart))
        if (tag == "meta"):
            def spanStart := spanHere()
            acceptTag("meta", ej)
            acceptTag(".", ej)
            def verb := acceptTag("IDENTIFIER", ej)
            if (verb[1] == "context"):
                acceptTag("(", ej)
                acceptTag(")", ej)
                return builder.MetaContextExpr(spanFrom(spanStart))
            if (verb[1] == "getState"):
                acceptTag("(", ej)
                acceptTag(")", ej)
                return builder.MetaStateExpr(spanFrom(spanStart))
            throw.eject(ej, [`Meta verbs are "context" or "getState"`, spanHere()])

        if (indent && peekTag() == "pass"):
            advance(ej)
            return builder.SeqExpr([], advance(ej)[2])
        throw.eject(tryAgain, [`don't recognize $tag`, spanHere()])

    bind blockExpr(ej):
        def origPosition := position
        escape e:
            return basic(true, e, ej)
        position := origPosition
        return expr(ej)
    "XXX buggy expander eats this line"

    bind prim(ej):
        def tag := peekTag()
        if ([".String.", ".int.", ".float64.", ".char."].contains(tag)):
            def t := advance(ej)
            return builder.LiteralExpr(t[1], t[2])
        if (tag == "IDENTIFIER"):
            def t := advance(ej)
            def nex := peekTag()
            if (nex == "QUASI_OPEN" || nex == "QUASI_CLOSE"):
                return quasiliteral(t, false, ej)
            else:
                return builder.NounExpr(t[1], t[2])
        if (tag == "::"):
            def spanStart := spanHere()
            advance(ej)
            def t := acceptTag(".String.", ej)
            return builder.NounExpr(t[1], t[2])
        if (tag == "QUASI_OPEN" || tag == "QUASI_CLOSE"):
            return quasiliteral(null, false, ej)
        if (tag == VALUE_HOLE):
            return builder.ValueHoleExpr(advance(ej)[1], spanHere())
        if (tag == PATTERN_HOLE):
            return builder.PatternHoleExpr(advance(ej)[1], spanHere())
        # paren expr
        if (tag == "("):
            advance(ej)
            acceptEOLs()
            def e := seq(false, ej)
            acceptEOLs()
            acceptTag(")", ej)
            return e
        # hideexpr
        if (tag == "{"):
            def spanStart := spanHere()
            advance(ej)
            acceptEOLs()
            if (peekTag() == "}"):
                advance(ej)
                return builder.HideExpr(builder.SeqExpr([], null), spanFrom(spanStart))
            def e := seq(false, ej)
            acceptEOLs()
            acceptTag("}", ej)
            return builder.HideExpr(e, spanFrom(spanStart))
        # list/map
        if (tag == "["):
            def spanStart := spanHere()
            advance(ej)
            acceptEOLs()
            if (peekTag() == "for"):
                advance(ej)
                def [k, v, it] := forExprHead(true, ej)
                def filt := if (peekTag() == "if") {
                    advance(ej)
                    acceptTag("(", ej)
                    acceptEOLs()
                    def e := expr(ej)
                    acceptEOLs()
                    acceptTag(")", ej)
                    e
                } else {
                    null
                }
                acceptEOLs()
                def body := expr(ej)
                if (peekTag() == "=>"):
                    advance(ej)
                    acceptEOLs()
                    def vbody := expr(ej)
                    acceptTag("]", ej)
                    return builder.MapComprehensionExpr(it, filt, k, v, body, vbody,
                        spanFrom(spanStart))
                acceptTag("]", ej)
                return builder.ListComprehensionExpr(it, filt, k, v, body,
                    spanFrom(spanStart))
            def [items, isMap] := acceptListOrMap(expr, mapItem)
            acceptEOLs()
            acceptTag("]", ej)
            if (isMap):
                return builder.MapExpr(items, spanFrom(spanStart))
            else:
                return builder.ListExpr(items, spanFrom(spanStart))
        return basic(false, ej, ej)
    "XXX buggy expander eats this line"
    def call(ej):
        def spanStart := spanHere()
        def base := prim(ej)
        def trailers := [].diverge()

        # XXX maybe parameterize mapItem instead of doing this
        def unpackMapItems(items):
            var pairs := []
            for node in items:
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
            def verb := if (peekTag() == ".String.") {
                advance(ej)[1]
            } else {
                def t := acceptTag("IDENTIFIER", ej)
                __makeString.fromString(t[1], t[2])
            }
            if (peekTag() == "("):
                advance(ej)
                def arglist := acceptList(positionalArg)
                def namedArglist := acceptList(mapItem)
                acceptEOLs()
                acceptTag(")", ej)
                trailers.push([methodish, [verb, arglist, unpackMapItems(namedArglist),
                                           spanFrom(spanStart)]])
                return false
            else:
                trailers.push(["CurryExpr", [verb, curryish, spanFrom(spanStart)]])
                return true

        def funcallish(name):
            acceptTag("(", ej)
            def arglist := acceptList(positionalArg)
            def namedArglist := acceptList(mapItem)
            acceptEOLs()
            acceptTag(")", ej)
            trailers.push([name, [arglist, unpackMapItems(namedArglist),
                                  spanFrom(spanStart)]])

        while (true):
            if (peekTag() == "."):
                advance(ej)
                if (callish("MethodCallExpr", false)):
                    break
            else if (peekTag() == "("):
                funcallish("FunCallExpr")
            else if (peekTag() == "<-"):
                advance(ej)
                if (peekTag() == "("):
                    funcallish("FunSendExpr")
                else:
                    if(callish("SendExpr", true)):
                        break
            else if (peekTag() == "["):
                advance(ej)
                def arglist := acceptList(expr)
                acceptEOLs()
                acceptTag("]", ej)
                trailers.push(["GetExpr", [arglist, spanFrom(spanStart)]])
            else:
                break
        var result := base
        for tr in trailers:
            result := M.call(builder, tr[0], [result] + tr[1], [].asMap())
        return result

    def prefix(ej):
        def spanStart := spanHere()
        def op := peekTag()
        if (op == "-"):
            advance(ej)
            return builder.PrefixExpr("-", prim(ej), spanFrom(spanStart))
        if (["~", "!"].contains(op)):
            advance(ej)
            return builder.PrefixExpr(op, call(ej), spanFrom(spanStart))
        if (op == "&"):
            advance(ej)
            return builder.SlotExpr(noun(ej), spanFrom(spanStart))
        if (op == "&&"):
            advance(ej)
            return builder.BindingExpr(noun(ej), spanFrom(spanStart))
        def base := call(ej)
        if (peekTag() == ":"):
            advance(ej)
            if (peekTag() == "EOL"):
                # oops, a token too far
                position -= 1
                return base
            return builder.CoerceExpr(base, guard(ej), spanFrom(spanHere()))
        return base
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
            # XXX buggy expander can't handle compound booleans
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
    "XXX buggy expander eats this line"

    def infix(ej):
        return convertInfix(10, ej)

    bind comp(ej):
        return convertInfix(8, ej)
    "XXX buggy expander eats this line"

    def _assign(ej):
        def spanStart := spanHere()
        def defStart := position
        if (peekTag() == "def"):
            advance(ej)
            def patt := pattern(ej)
            def ex := if (peekTag() == "exit") {
                advance(ej)
                order(ej)
            } else {
                null
            }
            # careful, this might be a trap
            if (peekTag() == ":="):
                advance(ej)
                return builder.DefExpr(patt, ex, assign(ej), spanFrom(spanStart))
            else:
                # bail out!
                position := defStart
                return basic(false, ej, ej)
        if (["var", "bind"].contains(peekTag())):
            def patt := pattern(ej)
            if (peekTag() == ":="):
                advance(ej)
                return builder.DefExpr(patt, null, assign(ej), spanFrom(spanStart))
            else:
                # curses, foiled again
                position := defStart
                return basic(false, ej, ej)
        def lval := infix(ej)
        if (peekTag() == ":="):
            advance(ej)
            def lt := lval.getNodeName()
            if (["NounExpr", "GetExpr"].contains(lt)):
                return builder.AssignExpr(lval, assign(ej), spanFrom(spanStart))
            throw.eject(ej, [`Invalid assignment target`, lt.getSpan()])
        if (peekTag() =~ `@op=`):
            advance(ej)
            def lt := lval.getNodeName()
            if (["NounExpr", "GetExpr"].contains(lt)):
                return builder.AugAssignExpr(op, lval, assign(ej), spanFrom(spanStart))
            throw.eject(ej, [`Invalid assignment target`, lt.getSpan()])
        if (peekTag() == "VERB_ASSIGN"):
            def verb := advance(ej)[1]
            def lt := lval.getNodeName()
            if (["NounExpr", "GetExpr"].contains(lt)):
                acceptTag("(", ej)
                acceptEOLs()
                def node := builder.VerbAssignExpr(verb, lval, acceptList(expr),
                     spanFrom(spanStart))
                acceptEOLs()
                acceptTag(")", ej)
                return node
            throw.eject(ej, [`Invalid assignment target`, lt.getSpan()])
        return lval
    bind assign := _assign

    def _expr(ej):
        if (["continue", "break", "return"].contains(peekTag())):
            def spanStart := spanHere()
            def ex := advanceTag(ej)
            if (peekTag() == "(" && tokens[position + 2][0] == ")"):
                position += 2
                return builder.ExitExpr(ex, null, spanFrom(spanStart))
            if (["EOL", "#", ";", "DEDENT", null].contains(peekTag())):
                return builder.ExitExpr(ex, null, spanFrom(spanStart))
            def val := blockExpr(ej)
            return builder.ExitExpr(ex, val, spanFrom(spanStart))
        return assign(ej)

    bind expr := _expr

    def module_(ej):
        def start := spanHere()
        def modKw := acceptTag("imports", ej)
        def importsList := acceptList(namedParam)
        acceptEOLs()
        def exportsList := if (peekTag() == "exports") {
            advance(ej)
            acceptTag("(", ej)
            def nouns := acceptList(noun)
            acceptTag(")", ej)
            acceptEOLs()
            nouns
        } else {[]}
        def body := seq(true, ej)
        return builder."Module"(importsList, exportsList, body,
                                spanFrom(start))

    def start(ej):
        acceptEOLs()
        if (peekTag() == "imports"):
            return module_(ej)
        else:
            return seq(true, ej)

    escape e:
        def val := switch (mode) {
            match =="module" {
                start(e)
            }
            match =="expression" {
                blockExpr(e)
            }
            match =="pattern" {
                pattern(e)
            }
        }
        acceptEOLs()
        if (position < (tokens.size() - 1)):
            formatError(lastError, err)
        else:
            return val
    catch p:
        formatError(p, err)


def parseExpression(lex, builder, err) as DeepFrozen:
    return parseMonte(lex, builder, "expression", err)

def parseModule(lex, builder, err) as DeepFrozen:
    return parseMonte(lex, builder, "module", err)

def parsePattern(lex, builder, err) as DeepFrozen:
    return parseMonte(lex, builder, "pattern", err)


[=> parseModule, => parseExpression, => parsePattern]
