import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
exports (makeMASTContext)

def packInt(var i :(Int >= 0)) :Bytes as DeepFrozen:
    if (i == 0):
        return b`$\x00`

    def l := [].diverge()
    while (i > 0):
        def chunk := i & 0x7f
        i >>= 7
        l.push(if (i > 0) {chunk | 0x80} else {chunk})
    return _makeBytes.fromInts(l)

def packRefs(bss :List[Bytes]) :Bytes as DeepFrozen:
    def size := packInt(bss.size())
    return size + b``.join(bss)

def packStr(s :NullOk[Str]) :Bytes as DeepFrozen:
    if (s == null) {return b`$\x00`}
    def bs := UTF8.encode(s, null)
    return packInt(bs.size()) + bs

def nullSpanBytes :Bytes := b`B$\x00$\x00$\x00$\x00`

def packSpan(s) :Bytes as DeepFrozen:
    if (s == null) { return nullSpanBytes }
    def type := if (s.isOneToOne()) { b`S` } else { b`B` }
    def startLine := packInt(s.getStartLine())
    def startCol := packInt(s.getStartCol())
    def endLine := packInt(s.getEndLine())
    def endCol := packInt(s.getEndCol())
    return type + startLine + startCol + endLine + endCol

def makeMASTContext() as DeepFrozen:
    "Make a MAST context."

    var exprIndex :Int := 0
    var pattIndex :Int := 0
    def streams := [b`Mont$\xe0MAST$\x01`].diverge()

    return object MASTContext:
        "A MAST context."

        to run(expr) :Void:
            "Add an expression to this context."
            MASTContext.appendExpr(expr)

        to bytes() :Bytes:
            return b``.join(streams)

        to appendExpr(expr) :Int:
            def bs :Bytes := MASTContext.addExpr(expr)
            def span := if (expr == null) { nullSpanBytes } else { packSpan(expr.getSpan()) }
            streams.push(bs + span)
            def rv := exprIndex
            exprIndex += 1
            return rv

        to packExpr(expr) :Bytes:
            return packInt(MASTContext.appendExpr(expr))

        to packExprs(exprs) :Bytes:
            def indices := [for expr in (exprs) MASTContext.packExpr(expr)]
            return packRefs(indices)

        to packNamedArgs(exprs) :Bytes:
            def namedArgs := [for na in (exprs)
                              MASTContext.packExpr(na.getKey()) + MASTContext.packExpr(na.getValue())]
            return packInt(namedArgs.size()) + b``.join(namedArgs)

        to appendPatt(patt) :Int:
            def bs :Bytes := MASTContext.addPatt(patt)
            def span := packSpan(patt.getSpan())
            streams.push(bs + span)
            def rv := pattIndex
            pattIndex += 1
            return rv

        to packPatt(patt) :Bytes:
            return packInt(MASTContext.appendPatt(patt))

        to packPatts(patts) :Bytes:
            def indices := [for patt in (patts) MASTContext.packPatt(patt)]
            return packRefs(indices)

        to packNamedPatt(patt) :Bytes:
            def k := MASTContext.packExpr(patt.getKey())
            def p := MASTContext.packPatt(patt.getValue())
            def e := MASTContext.packExpr(patt.getDefault())
            return k + p + e

        to packNamedPatts(patts) :Bytes:
            def namedPatts := [for patt in (patts)
                               MASTContext.packNamedPatt(patt)]
            return packInt(namedPatts.size()) + b``.join(namedPatts)

        to addExpr(expr) :Bytes:
            if (expr == null) { return b`LN` }
            # traceln(expr.getNodeName())
            return switch (expr.getNodeName()):
                match =="LiteralExpr":
                    switch (expr.getValue()):
                        match ==null:
                            b`LN`
                        match c :Char:
                            # Not likely to fail, so not creating an ejector.
                            def bs := UTF8.encode(c.asString(), null)
                            b`LC$bs`
                        match d :Double:
                            def bs := d.toBytes()
                            b`LD$bs`
                        match i :Int:
                            def zz := if (i < 0) {((i << 1) ^ -1) | 1} else {i << 1}
                            def bs := packInt(zz)
                            b`LI$bs`
                        match s :Str:
                            def bs := packStr(s)
                            b`LS$bs`
                match =="NounExpr":
                    def s := packStr(expr.getName())
                    b`N$s`
                match =="BindingExpr":
                    def s := packStr(expr.getNoun().getName())
                    b`B$s`
                match =="SeqExpr":
                    def exprs := MASTContext.packExprs(expr.getExprs())
                    b`S$exprs`
                match =="MethodCallExpr":
                    def target := MASTContext.packExpr(expr.getReceiver())
                    def verb := packStr(expr.getVerb())
                    def args := MASTContext.packExprs(expr.getArgs())
                    def namedArgs := MASTContext.packNamedArgs(expr.getNamedArgs())
                    b`C$target$verb$args$namedArgs`
                match =="DefExpr":
                    def patt := MASTContext.packPatt(expr.getPattern())
                    def exit_ := MASTContext.packExpr(expr.getExit())
                    def e := MASTContext.packExpr(expr.getExpr())
                    b`D$patt$exit_$e`
                match =="EscapeExpr":
                    def escapePatt := MASTContext.packPatt(expr.getEjectorPattern())
                    def escapeExpr := MASTContext.packExpr(expr.getBody())
                    if (expr.getCatchPattern() == null) {
                        b`e$escapePatt$escapeExpr`
                    } else {
                        def catchPatt := MASTContext.packPatt(expr.getCatchPattern())
                        def catchExpr := MASTContext.packExpr(expr.getCatchBody())
                        b`E$escapePatt$escapeExpr$catchPatt$catchExpr`
                    }
                match =="ObjectExpr":
                    def doc := packStr(expr.getDocstring())
                    def patt := MASTContext.packPatt(expr.getName())
                    def asExpr := MASTContext.packExpr(expr.getAsExpr())
                    def auditors := MASTContext.packExprs(expr.getAuditors())
                    def script := expr.getScript()
                    def methods := MASTContext.packExprs(script.getMethods())
                    def matchers := MASTContext.packExprs(script.getMatchers())
                    b`O$doc$patt$asExpr$auditors$methods$matchers`
                match =="Method":
                    def doc := packStr(expr.getDocstring())
                    def verb := packStr(expr.getVerb())
                    def patts := MASTContext.packPatts(expr.getParams())
                    def namedPatts := MASTContext.packNamedPatts(expr.getNamedParams())
                    def guard := MASTContext.packExpr(expr.getResultGuard())
                    def body := MASTContext.packExpr(expr.getBody())
                    b`M$doc$verb$patts$namedPatts$guard$body`
                match =="Matcher":
                    def patt := MASTContext.packPatt(expr.getPattern())
                    def body := MASTContext.packExpr(expr.getBody())
                    b`R$patt$body`
                match =="AssignExpr":
                    def lvalue := packStr(expr.getLvalue().getName())
                    def rvalue := MASTContext.packExpr(expr.getRvalue())
                    b`A$lvalue$rvalue`
                match =="FinallyExpr":
                    def try_ := MASTContext.packExpr(expr.getBody())
                    def finally_ := MASTContext.packExpr(expr.getUnwinder())
                    b`F$try_$finally_`
                match =="CatchExpr":
                    def try_ := MASTContext.packExpr(expr.getBody())
                    def catchPatt := MASTContext.packPatt(expr.getPattern())
                    def catchExpr := MASTContext.packExpr(expr.getCatcher())
                    b`Y$try_$catchPatt$catchExpr`
                match =="HideExpr":
                    def body := MASTContext.packExpr(expr.getBody())
                    b`H$body`
                match =="IfExpr":
                    def if_ := MASTContext.packExpr(expr.getTest())
                    def then_ := MASTContext.packExpr(expr.getThen())
                    def else_ := MASTContext.packExpr(expr.getElse())
                    b`I$if_$then_$else_`
                match =="MetaStateExpr":
                    b`T`
                match =="MetaContextExpr":
                    b`X`

        to addPatt(patt) :Bytes:
            return switch (patt.getNodeName()):
                match =="FinalPattern":
                    def name := packStr(patt.getNoun().getName())
                    def guard := MASTContext.packExpr(patt.getGuard())
                    b`PF$name$guard`
                match =="IgnorePattern":
                    def guard := MASTContext.packExpr(patt.getGuard())
                    b`PI$guard`
                match =="VarPattern":
                    def name := packStr(patt.getNoun().getName())
                    def guard := MASTContext.packExpr(patt.getGuard())
                    b`PV$name$guard`
                match =="ListPattern":
                    def patts := MASTContext.packPatts(patt.getPatterns())
                    b`PL$patts`
                match =="ViaPattern":
                    def expr := MASTContext.packExpr(patt.getExpr())
                    def innerPatt := MASTContext.packPatt(patt.getPattern())
                    b`PA$expr$innerPatt`
                match =="BindingPattern":
                    def name := packStr(patt.getNoun().getName())
                    b`PB$name`
