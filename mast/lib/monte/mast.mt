imports => UTF8 :DeepFrozen
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

def makeMASTContext() as DeepFrozen:
    "Make a MAST context."

    def exprs := [].diverge()
    def patts := [].diverge()
    def streams := [b`Mont$\xe0MAST$\x00`].diverge()

    return object MASTContext:
        "A MAST context."

        to run(expr) :Void:
            MASTContext.addExpr(expr)

        to bytes() :Bytes:
            return b``.join(streams)

        to appendExpr(bs :Bytes) :Int:
            var index := exprs.indexOf(bs)
            if (index == -1):
                index := exprs.size()
                exprs.push(bs)
                streams.push(bs)
            return index

        to packExpr(expr) :Bytes:
            return packInt(MASTContext.addExpr(expr))

        to packExprs(exprs) :Bytes:
            def indices := [for expr in (exprs) MASTContext.packExpr(expr)]
            return packRefs(indices)

        to packNamedArgs(exprs) :Bytes:
            def namedArgs := [for na in (exprs)
                              MASTContext.packExpr(na.getKey()) + MASTContext.packExpr(na.getValue())]
            return packInt(namedArgs.size()) + b``.join(namedArgs)

        to appendPatt(bs :Bytes) :Int:
            var index := patts.indexOf(bs)
            if (index == -1):
                index := patts.size()
                patts.push(bs)
                streams.push(bs)
            return index

        to packPatt(patt) :Bytes:
            return packInt(MASTContext.addPatt(patt))

        to packPatts(patts) :Bytes:
            def indices := [for patt in (patts) MASTContext.packPatt(patt)]
            return packRefs(indices)

        to packNamedPatt(patt) :Bytes:
            def k := MASTContext.packExpr(patt.getKey())
            def p := MASTContext.packPatt(patt.getPattern())
            def e := MASTContext.packExpr(patt.getDefault())
            return k + p + e

        to packNamedPatts(patts) :Bytes:
            def namedPatts := [for patt in (patts)
                               MASTContext.packNamedPatt(patt)]
            return packInt(namedPatts.size()) + b``.join(namedPatts)

        to addExpr(expr) :Int:
            if (expr == null) {return MASTContext.appendExpr(b`LN`)}
            # traceln(expr.getNodeName())
            return switch (expr.getNodeName()):
                match =="LiteralExpr":
                    switch (expr.getValue()):
                        match ==null:
                            MASTContext.appendExpr(b`LN`)
                        match c :Char:
                            # Not likely to fail, so not creating an ejector.
                            def bs := UTF8.encode(c.asString(), null)
                            MASTContext.appendExpr(b`LC$bs`)
                        match d :Double:
                            def bs := d.toBytes()
                            MASTContext.appendExpr(b`LD$bs`)
                        match i :Int:
                            def zz := if (i < 0) {((i << 1) ^ -1) | 1} else {i << 1}
                            def bs := packInt(zz)
                            MASTContext.appendExpr(b`LI$bs`)
                        match s :Str:
                            def bs := packStr(s)
                            MASTContext.appendExpr(b`LS$bs`)
                match =="NounExpr":
                    def s := packStr(expr.getName())
                    MASTContext.appendExpr(b`N$s`)
                match =="BindingExpr":
                    def s := packStr(expr.getNoun().getName())
                    MASTContext.appendExpr(b`B$s`)
                match =="SeqExpr":
                    def exprs := MASTContext.packExprs(expr.getExprs())
                    MASTContext.appendExpr(b`S$exprs`)
                match =="MethodCallExpr":
                    def target := MASTContext.packExpr(expr.getReceiver())
                    def verb := packStr(expr.getVerb())
                    def args := MASTContext.packExprs(expr.getArgs())
                    def namedArgs := MASTContext.packNamedArgs(expr.getNamedArgs())
                    def bs := b`C$target$verb$args$namedArgs`
                    MASTContext.appendExpr(bs)
                match =="DefExpr":
                    def patt := MASTContext.packPatt(expr.getPattern())
                    def exit_ := MASTContext.packExpr(expr.getExit())
                    def e := MASTContext.packExpr(expr.getExpr())
                    MASTContext.appendExpr(b`D$patt$exit_$e`)
                match =="EscapeExpr":
                    def escapePatt := MASTContext.packPatt(expr.getEjectorPattern())
                    def escapeExpr := MASTContext.packExpr(expr.getBody())
                    def bs := if (expr.getCatchPattern() == null) {
                        b`e$escapePatt$escapeExpr`
                    } else {
                        def catchPatt := MASTContext.packPatt(expr.getCatchPattern())
                        def catchExpr := MASTContext.packExpr(expr.getCatchBody())
                        b`E$escapePatt$escapeExpr$catchPatt$catchExpr`
                    }
                    MASTContext.appendExpr(bs)
                match =="ObjectExpr":
                    def doc := packStr(expr.getDocstring())
                    def patt := MASTContext.packPatt(expr.getName())
                    def asExpr := MASTContext.packExpr(expr.getAsExpr())
                    def auditors := MASTContext.packExprs(expr.getAuditors())
                    def script := expr.getScript()
                    def methods := MASTContext.packExprs(script.getMethods())
                    def matchers := MASTContext.packExprs(script.getMatchers())
                    def bs := b`O$doc$patt$asExpr$auditors$methods$matchers`
                    MASTContext.appendExpr(bs)
                match =="Method":
                    def doc := packStr(expr.getDocstring())
                    def verb := packStr(expr.getVerb())
                    def patts := MASTContext.packPatts(expr.getPatterns())
                    def namedPatts := MASTContext.packNamedPatts(expr.getNamedPatterns())
                    def guard := MASTContext.packExpr(expr.getResultGuard())
                    def body := MASTContext.packExpr(expr.getBody())
                    def bs := b`M$doc$verb$patts$namedPatts$guard$body`
                    MASTContext.appendExpr(bs)
                match =="Matcher":
                    def patt := MASTContext.packPatt(expr.getPattern())
                    def body := MASTContext.packExpr(expr.getBody())
                    MASTContext.appendExpr(b`R$patt$body`)
                match =="AssignExpr":
                    def lvalue := packStr(expr.getLvalue().getName())
                    def rvalue := MASTContext.packExpr(expr.getRvalue())
                    MASTContext.appendExpr(b`A$lvalue$rvalue`)
                match =="FinallyExpr":
                    def try_ := MASTContext.packExpr(expr.getBody())
                    def finally_ := MASTContext.packExpr(expr.getUnwinder())
                    MASTContext.appendExpr(b`F$try_$finally_`)
                match =="CatchExpr":
                    def try_ := MASTContext.packExpr(expr.getBody())
                    def catchPatt := MASTContext.packPatt(expr.getPattern())
                    def catchExpr := MASTContext.packExpr(expr.getCatcher())
                    MASTContext.appendExpr(b`Y$try_$catchPatt$catchExpr`)
                match =="HideExpr":
                    def body := MASTContext.packExpr(expr.getBody())
                    MASTContext.appendExpr(b`H$body`)
                match =="IfExpr":
                    def if_ := MASTContext.packExpr(expr.getTest())
                    def then_ := MASTContext.packExpr(expr.getThen())
                    def else_ := MASTContext.packExpr(expr.getElse())
                    MASTContext.appendExpr(b`I$if_$then_$else_`)
                match =="MetaStateExpr":
                    MASTContext.appendExpr(b`T`)
                match =="MetaContextExpr":
                    MASTContext.appendExpr(b`X`)

        to addPatt(patt) :Int:
            return switch (patt.getNodeName()):
                match =="FinalPattern":
                    def name := packStr(patt.getNoun().getName())
                    def guard := MASTContext.packExpr(patt.getGuard())
                    MASTContext.appendPatt(b`PF$name$guard`)
                match =="IgnorePattern":
                    def guard := MASTContext.packExpr(patt.getGuard())
                    MASTContext.appendPatt(b`PI$guard`)
                match =="VarPattern":
                    def name := packStr(patt.getNoun().getName())
                    def guard := MASTContext.packExpr(patt.getGuard())
                    MASTContext.appendPatt(b`PV$name$guard`)
                match =="ListPattern":
                    def patts := MASTContext.packPatts(patt.getPatterns())
                    MASTContext.appendPatt(b`PL$patts`)
                match =="ViaPattern":
                    def expr := MASTContext.packExpr(patt.getExpr())
                    def innerPatt := MASTContext.packPatt(patt.getPattern())
                    MASTContext.appendPatt(b`PA$expr$innerPatt`)
                match =="BindingPattern":
                    def name := packStr(patt.getNoun().getName())
                    MASTContext.appendPatt(b`PB$name`)
