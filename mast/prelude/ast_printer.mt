import "boot" =~ [=> DeepFrozenStamp]
exports (printerActions)

def all(iterable, pred) as DeepFrozenStamp:
    for item in (iterable):
        if (!pred(item)):
            return false
    return true

def MONTE_KEYWORDS :List[Str] := [
"as", "bind", "break", "catch", "continue", "def", "else", "escape",
"exit", "extends", "exports", "finally", "fn", "for", "guards", "if",
"implements", "in", "interface", "match", "meta", "method", "module",
"object", "pass", "pragma", "return", "switch", "to", "try", "var",
"via", "when", "while", "_"]

def idStart :List[Char] := _makeList.fromIterable("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
def idPart :List[Char] := idStart + _makeList.fromIterable("0123456789")
def INDENT :Str := "    "

# note to future drunk self: lower precedence number means add parens when
# inside a higher-precedence-number expression
def priorities :Map[Str, Int] := [
     "indentExpr" => 0,
     "braceExpr" => 1,
     "assign" => 2,
     "logicalOr" => 3,
     "logicalAnd" => 4,
     "comp" => 5,
     "order" => 6,
     "interval" => 7,
     "shift" => 8,
     "addsub" => 9,
     "divmul" => 10,
     "pow" => 11,
     "prefix" => 12,
     "send" => 13,
     "coerce" => 14,
     "call" => 15,
     "prim" => 16,

     "pattern" => 0]

def isIdentifier(name :Str) :Bool as DeepFrozenStamp:
    if (MONTE_KEYWORDS.contains(name.toLowerCase())):
        return false
    return idStart.contains(name[0]) && all(name.slice(1), idPart.contains)

def printListOn(left, nodes, sep, right, out, priority) as DeepFrozenStamp:
    out.print(left)
    if (nodes.size() >= 1):
        for n in (nodes.slice(0, nodes.size() - 1)):
            n.subPrintOn(out, priority)
            out.print(sep)
        nodes.last().subPrintOn(out, priority)
    out.print(right)

def printDocstringOn(docstring, out, indentLastLine) as DeepFrozenStamp:
    if (docstring == null):
        if (indentLastLine):
            out.println("")
        return
    out.lnPrint("\"")
    def lines := docstring.split("\n")
    for line in (lines.slice(0, 0.max(lines.size() - 2))):
        out.println(line)
    if (lines.size() > 0):
        out.print(lines.last())
    if (indentLastLine):
        out.println("\"")
    else:
        out.print("\"")

def printSuiteOn(leaderFn, printContents, cuddle, noLeaderNewline, out,
                 priority) as DeepFrozenStamp:
    def indentOut := out.indent(INDENT)
    if (priorities["braceExpr"] <= priority):
        if (cuddle):
            out.print(" ")
        leaderFn()
        if (noLeaderNewline):
            indentOut.print(" {")
        else:
            indentOut.println(" {")
        printContents(indentOut, priorities["braceExpr"])
        out.println("")
        out.print("}")
    else:
        if (cuddle):
            out.println("")
        leaderFn()
        if (noLeaderNewline):
            indentOut.print(":")
        else:
            indentOut.println(":")
        printContents(indentOut, priorities["indentExpr"])

def printExprSuiteOn(leaderFn, suite, cuddle, out, priority) as DeepFrozenStamp:
    printSuiteOn(leaderFn, suite.subPrintOn, cuddle, false, out, priority)

def printDocExprSuiteOn(leaderFn, docstring, suite, out, priority) as DeepFrozenStamp:
    printSuiteOn(leaderFn, fn o, p {
        printDocstringOn(docstring, o, true)
        suite.subPrintOn(o, p)
        }, false, true, out, priority)

def printObjectSuiteOn(leaderFn, docstring, suite, out, priority) as DeepFrozenStamp:
    printSuiteOn(leaderFn, fn o, p {
        printDocstringOn(docstring, o, false)
        suite.subPrintOn(o, p)
        }, false, true, out, priority)

def printObjectHeadOn(script, name, asExpr, auditors, out, _priority) as DeepFrozenStamp:
    def namedPatterns := script.getNamedPatterns()
    def patterns := script.getPatterns()
    def resultGuard := script.getResultGuard()
    def verb := script.getVerb()
    if (script.getNodeName() == "FunctionScript"):
        out.print("def ")
        name.subPrintOn(out, priorities["pattern"])
        if (verb != "run"):
            out.print(".")
            if (isIdentifier()):
                out.print(verb)
            else:
                out.quote(verb)
        printListOn("(", patterns, ", ", "", out, priorities["pattern"])
        printListOn("", namedPatterns, ", ", ")", out, priorities["pattern"])
        if (resultGuard != null):
            out.print(" :")
            resultGuard.subPrintOn(out, priorities["call"])
        if (asExpr != null):
            out.print(" as ")
            asExpr.subPrintOn(out, priorities["call"])
        if (auditors.size() > 0):
            printListOn(" implements ", auditors, ", ", "", out, priorities["call"])
    else:
        def extend := script.getExtends()
        out.print("object ")
        name.subPrintOn(out, priorities["pattern"])
        if (asExpr != null):
            out.print(" as ")
            asExpr.subPrintOn(out, priorities["call"])
        if (auditors.size() > 0):
            printListOn(" implements ", auditors, ", ", "", out, priorities["call"])
        if (extend != null):
            out.print(" extends ")
            extend.subPrintOn(out, priorities["order"])


def quasiPrint(name, quasis, out) as DeepFrozenStamp:
    if (name != null):
        out.print(name)
    out.print("`")
    for i => q in (quasis):
        var p := priorities["prim"]
        if (i + 1 < quasis.size()):
            def next := quasis[i + 1]
            if (next.getNodeName() == "QuasiText"):
                if (next.getText().size() > 0 && idPart.contains(next.getText()[0])):
                    p := priorities["braceExpr"]
        q.subPrintOn(out, p)
    out.print("`")

def printerActions :Map[Str, DeepFrozen] := [
    "MetaContextExpr" => def printMetaContextExpr(_self, out, _priority) as DeepFrozenStamp {
        out.print("meta.context()")
    },
    "MetaStateExpr" => def printMetaStateExpr(_self, out, _priority) as DeepFrozenStamp {
        out.print("meta.getState()")
    },
    "LiteralExpr" => def printLiteralExpr(self, out, _priority) as DeepFrozenStamp {
        out.quote(self.getValue())
    },
    "NounExpr" => def printNounExpr(self, out, _priority) as DeepFrozenStamp {
        def name := self.getName()
        if (isIdentifier(name)) {
        out.print(name)
        } else {
            out.print("::")
            out.quote(name)
        }
    },
    "BindingExpr" => def printBindingExpr(self, out, _priority) as DeepFrozenStamp {
        out.print("&&")
        out.print(self.getNoun())
    },
    "SlotExpr" => def printSlotExpr(self, out, _priority) as DeepFrozenStamp {
        out.print("&")
        out.print(self.getNoun())
    },
    "SeqExpr" => def printSeqExpr(self, out, priority) as DeepFrozenStamp {
        if (priority > priorities["braceExpr"]) {
            out.print("(")
        }
        var first := true
        if (priorities["braceExpr"] >= priority && self.getExprs() == []) {
            out.print("pass")
        }
        for e in (self.getExprs()) {
            if (!first) {
                out.println("")
            }
            first := false
            e.subPrintOn(out, priority.min(priorities["braceExpr"]))
        }
        if (priority > priorities["braceExpr"]) {
            out.print(")")
        }
    },
    "Module" => def printModule(self, out, _priority) as DeepFrozenStamp {
        for [petname, patt] in (self.getImports()) {
            out.print("import ")
            out.quote(petname)
            out.print(" =~ ")
            out.println(patt)
        }
        def exportsList := self.getExports()
        if (exportsList.size() > 0) {
            out.print("exports ")
            printListOn("(", exportsList, ", ", ")", out, priorities["braceExpr"])
            out.println("")
        }
        self.getBody().subPrintOn(out, priorities["indentExpr"])
    },
    "NamedArg" => def printNamedArg(self, out, _priority) as DeepFrozenStamp {
        self.getKey().subPrintOn(out, priorities["prim"])
        out.print(" => ")
        self.getValue().subPrintOn(out, priorities["braceExpr"])
    },
    "NamedArgExport" => def printNamedArgExport(self, out, _priority) as DeepFrozenStamp {
        out.print(" => ")
        self.getValue().subPrintOn(out, "braceExpr")
    },
    "MethodCallExpr" => def printMethodCallExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        out.print(".")
        def verb := self.getVerb()
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        printListOn("(", self.getArgs() + self.getNamedArgs(), ", ",
                    ")", out, priorities["braceExpr"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "FunCallExpr" => def printFunCallExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        printListOn("(", self.getArgs() + self.getNamedArgs(),
                    ", ", ")", out, priorities["braceExpr"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "SendExpr" => def printSendExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        out.print(" <- ")
        def verb := self.getVerb()
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        printListOn("(", self.getArgs() + self.getNamedArgs(),
                    ", ", ")", out, priorities["braceExpr"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "FunSendExpr" => def printFunSendExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        printListOn(" <- (", self.getArgs() + self.getNamedArgs(),
                    ", ", ")", out, priorities["braceExpr"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "GetExpr" => def printGetExpr(self, out, _priority) as DeepFrozenStamp {
        self.getReceiver().subPrintOn(out, priorities["call"])
        printListOn("[", self.getIndices(), ", ", "]", out, priorities["braceExpr"])
        },
    "AndExpr" => def printAndExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["logicalAnd"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["logicalAnd"])
        out.print(" && ")
        self.getRight().subPrintOn(out, priorities["logicalAnd"])
        if (priorities["logicalAnd"] < priority) {
            out.print(")")
        }
    },
    "OrExpr" => def printOrExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["logicalOr"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["logicalOr"])
        out.print(" || ")
        self.getRight().subPrintOn(out, priorities["logicalOr"])
        if (priorities["logicalOr"] < priority) {
            out.print(")")
        }
    },
    "BinaryExpr" => def printBinaryExpr(self, out, priority) as DeepFrozenStamp {
        def opPrio := priorities[self.getPriorityName()]
        if (opPrio < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, opPrio)
        out.print(" ")
        out.print(self.getOp())
        out.print(" ")
        self.getRight().subPrintOn(out, opPrio)
        if (opPrio < priority) {
            out.print(")")
        }
    },
    "CompareExpr" => def printCompareExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["comp"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["comp"])
        out.print(" ")
        out.print(self.getOp())
        out.print(" ")
        self.getRight().subPrintOn(out, priorities["comp"])
        if (priorities["comp"] < priority) {
            out.print(")")
        }
    },
    "RangeExpr" => def printRangeExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["interval"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["interval"])
        out.print(self.getOp())
        self.getRight().subPrintOn(out, priorities["interval"])
        if (priorities["interval"] < priority) {
            out.print(")")
        }
    },
    "SameExpr" => def printSameExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["comp"] < priority) {
            out.print("(")
        }
        self.getLeft().subPrintOn(out, priorities["comp"])
        if (self.getDirection()) {
            out.print(" == ")
        } else {
            out.print(" != ")
        }
        self.getRight().subPrintOn(out, priorities["comp"])
        if (priorities["comp"] < priority) {
            out.print(")")
        }
    },
    "MatchBindExpr" => def printMatchBindExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getSpecimen().subPrintOn(out, priorities["call"])
        out.print(" =~ ")
        self.getPattern().subPrintOn(out, priorities["pattern"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "MismatchExpr" => def printMismatchExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getSpecimen().subPrintOn(out, priorities["call"])
        out.print(" !~ ")
        self.getPattern().subPrintOn(out, priorities["pattern"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "PrefixExpr" => def printPrefixExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        out.print(self.getOp())
        self.getReceiver().subPrintOn(out, priorities["call"])
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "CoerceExpr" => def printCoerceExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["coerce"] < priority) {
            out.print("(")
        }
        self.getSpecimen().subPrintOn(out, priorities["coerce"])
        out.print(" :")
        self.getGuard().subPrintOn(out, priorities["prim"])
        if (priorities["coerce"] < priority) {
            out.print(")")
        }
    },
    "CurryExpr" => def printCurryExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        self.getReceiver().subPrintOn(out, priorities["call"])
        if (self.getIsSend()) {
            out.print(" <- ")
        } else {
            out.print(".")
        }
        def verb := self.getVerb()
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        if (priorities["call"] < priority) {
            out.print(")")
        }
   },
    "ExitExpr" => def printExitExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["call"] < priority) {
            out.print("(")
        }
        out.print(self.getName())
        if (self.getValue() != null) {
            out.print(" ")
            self.getValue().subPrintOn(out, priority)
        }
        if (priorities["call"] < priority) {
            out.print(")")
        }
    },
    "ForwardExpr" => def printForwardExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        out.print("def ")
        self.getNoun().subPrintOn(out, priorities["prim"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "DefExpr" => def printDefExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        def pattern := self.getPattern()
        if (!["VarPattern", "BindPattern"].contains(pattern.getNodeName())) {
            out.print("def ")
        }
        pattern.subPrintOn(out, priorities["pattern"])
        def exit_ := self.getExit()
        if (exit_ != null) {
            out.print(" exit ")
            exit_.subPrintOn(out, priorities["call"])
        }
        out.print(" := ")
        self.getExpr().subPrintOn(out, priorities["assign"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "AssignExpr" => def printAssignExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        self.getLvalue().subPrintOn(out, priorities["call"])
        out.print(" := ")
        self.getRvalue().subPrintOn(out, priorities["assign"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "VerbAssignExpr" => def printVerbAssignExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        self.getLvalue().subPrintOn(out, priorities["call"])
        out.print(" ")
        def verb := self.getVerb()
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        out.print("= ")
        printListOn("(", self.getRvalues(), ", ", ")", out,
                    priorities["assign"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "AugAssignExpr" => def printAugAssignExpr(self, out, priority) as DeepFrozenStamp {
        if (priorities["assign"] < priority) {
            out.print("(")
        }
        self.getLvalue().subPrintOn(out, priorities["call"])
        out.print(" ")
        out.print(self.getOp())
        out.print("= ")
        self.getRvalue().subPrintOn(out, priorities["assign"])
        if (priorities["assign"] < priority) {
            out.print(")")
        }
    },
    "Method" => def printMethod(self, out, priority) as DeepFrozenStamp {
        printDocExprSuiteOn(fn {
            out.lnPrint("method ")
            def verb := self.getVerb()
            def patterns := self.getPatterns()
            def namedPatts := self.getNamedPatterns()
            def resultGuard := self.getResultGuard()
            if (isIdentifier(verb)) {
                out.print(verb)
            } else {
                out.quote(verb)
            }
            printListOn("(", patterns, ", ", "", out, priorities["pattern"])
            if (patterns.size() > 0 && namedPatts.size() > 0) {
                out.print(", ")
            }
            printListOn("", namedPatts, ", ", ")", out, priorities["pattern"])
            if (resultGuard != null) {
                out.print(" :")
                resultGuard.subPrintOn(out, priorities["call"])
            }
        }, self.getDocstring(), self.getBody(), out, priority)
    },
    "To" => def printTo(self, out, priority) as DeepFrozenStamp {
        printDocExprSuiteOn(fn {
            out.lnPrint("to ")
            def verb := self.getVerb()
            def patterns := self.getPatterns()
            def namedPatts := self.getNamedPatterns()
            def resultGuard := self.getResultGuard()
            if (isIdentifier(verb)) {
                out.print(verb)
            } else {
                out.quote(verb)
            }
            printListOn("(", patterns, ", ", "", out, priorities["pattern"])
            if (patterns.size() > 0 && namedPatts.size() > 0) {
                out.print(", ")
            }
            printListOn("", namedPatts, ", ", ")", out, priorities["pattern"])
            if (resultGuard != null) {
                out.print(" :")
                resultGuard.subPrintOn(out, priorities["call"])
            }
        }, self.getDocstring(), self.getBody(), out, priority)
    },
    "Matcher" => def printMatcher(self, out, priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {
            out.lnPrint("match ")
            self.getPattern().subPrintOn(out, priorities["pattern"])
        }, self.getBody(), false, out, priority)
    },
    "Catcher" => def printCatcher(self, out, priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {
            out.print("catch ")
            self.getPattern().subPrintOn(out, priorities["pattern"])
        }, self.getBody(), true, out, priority)
    },
    "Script" => def printScript(self, out, priority) as DeepFrozenStamp {
        for m in (self.getMethods() + self.getMatchers()) {
            m.subPrintOn(out, priority)
            out.print("\n")
        }
    },
    "FunctionScript" => def printFunctionScript(self, out, priority) as DeepFrozenStamp {
        self.getBody().subPrintOn(out, priority)
        out.print("\n")
    },
    "FunctionExpr" => def printFunctionExpr(self, out, _priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {
            printListOn("fn ", self.getPatterns(), ", ",
                        "", out, priorities["pattern"])
            printListOn("", self.getNamedPatterns(), ", ",
                        "", out, priorities["pattern"])
        }, self.getBody(), false, out, priorities["assign"])
 },
    "ListExpr" => def printListExpr(self, out, _priority) as DeepFrozenStamp {
        printListOn("[", self.getItems(), ", ", "]", out, priorities["braceExpr"])
    },
    "ListComprehensionExpr" => def printListComprehensionExpr(self, out, _priority) as DeepFrozenStamp {
        out.print("[for ")
        def key := self.getKey()
        def value := self.getValue()
        def iterable := self.getIterable()
        def filter := self.getFilter()
        if (key != null) {
            key.subPrintOn(out, priorities["pattern"])
            out.print(" => ")
        }
        value.subPrintOn(out, priorities["pattern"])
        out.print(" in (")
        iterable.subPrintOn(out, priorities["braceExpr"])
        out.print(") ")
        if (filter != null) {
            out.print("if (")
            filter.subPrintOn(out, priorities["braceExpr"])
            out.print(") ")
        }
        self.getBody().subPrintOn(out, priorities["braceExpr"])
        out.print("]")
    },
    "MapExprAssoc" => def printMapExprAssoc(self, out, _priority) as DeepFrozenStamp {
        self.getKey().subPrintOn(out, priorities["braceExpr"])
        out.print(" => ")
        self.getValue().subPrintOn(out, priorities["braceExpr"])
    },
    "MapExprExport" => def printMapExprExport(self, out, _priority) as DeepFrozenStamp {
        out.print("=> ")
        self.getValue().subPrintOn(out, priorities["prim"])
    },
    "MapExpr" => def printMapExpr(self, out, _priority) as DeepFrozenStamp {
        printListOn("[", self.getPairs(), ", ", "]", out, priorities["braceExpr"])
    },
    "MapComprehensionExpr" => def printMapComprehensionExpr(self, out, _priority) as DeepFrozenStamp {
        def key := self.getKey()
        def value := self.getValue()
        def iterable := self.getIterable()
        def filter := self.getFilter()
        out.print("[for ")
        if (key != null) {
            key.subPrintOn(out, priorities["pattern"])
            out.print(" => ")
        }
        value.subPrintOn(out, priorities["pattern"])
        out.print(" in (")
        iterable.subPrintOn(out, priorities["braceExpr"])
        out.print(") ")
        if (filter != null) {
            out.print("if (")
            filter.subPrintOn(out, priorities["braceExpr"])
            out.print(") ")
        }
        self.getBodyKey().subPrintOn(out, priorities["braceExpr"])
        out.print(" => ")
        self.getBodyValue().subPrintOn(out, priorities["braceExpr"])
        out.print("]")
    },
    "ForExpr" => def printForExpr(self, out, priority) as DeepFrozenStamp {
        def key := self.getKey()
        def value := self.getValue()
        def iterable := self.getIterable()
        printExprSuiteOn(fn {
            out.print("for ")
            if (key != null) {
                key.subPrintOn(out, priorities["pattern"])
                out.print(" => ")
            }
            value.subPrintOn(out, priorities["pattern"])
            out.print(" in ")
            iterable.subPrintOn(out, priorities["braceExpr"])
        }, self.getBody(), false, out, priority)
        def catchPattern := self.getCatchPattern()
        if (catchPattern != null) {
            printExprSuiteOn(fn {
                out.print("catch ")
                catchPattern.subPrintOn(out, priorities["pattern"])
            }, self.getCatchBody(), true, out, priority)
        }
    },
    "ObjectExpr" => def printObjectExpr(self, out, priority) as DeepFrozenStamp {
        def script := self.getScript()
        def printIt := if (script.getNodeName() == "FunctionScript") {
            printDocExprSuiteOn
        } else {
            printObjectSuiteOn
        }
        printIt(fn {
            printObjectHeadOn(
                script, self.getName(), self.getAsExpr(),
                self.getAuditors(), out, priority)
        }, self.getDocstring(), self.getScript(), out, priority)
    },
    "ParamDesc" => def printParamDesc(self, out, _priority) as DeepFrozenStamp {
        def name := self.getName()
        if (name == null) {
            out.print("_")
        } else {
            out.print(name)
        }
        def guard := self.getGuard()
        if (guard != null) {
            out.print(" :")
            guard.subPrintOn(out, priorities["call"])
        }
    },
    "MessageDesc" => def printMessageDesc(self, out, priority) as DeepFrozenStamp {
        def head := self.getHead()
        def verb := self.getVerb()
        def params := self.getParams()
        def namedParams := self.getNamedParams()
        def resultGuard := self.getResultGuard()
        def docstring := self.getDocstring()
        #XXX hacckkkkkk
        if (head == "to") {
            out.println("")
        }
        out.print(head)
        out.print(" ")
        if (isIdentifier(verb)) {
            out.print(verb)
        } else {
            out.quote(verb)
        }
        printListOn("(", params, ", ", "", out, priorities["pattern"])
        if (params.size() > 0 && namedParams.size() > 0) {
            out.print(", ")
        }
        printListOn("", namedParams, ", ", ")", out, priorities["pattern"])
        if (resultGuard != null) {
            out.print(" :")
            resultGuard.subPrintOn(out, priorities["call"])
        }
        if (docstring != null) {
            def bracey := priorities["braceExpr"] <= priority
            def indentOut := out.indent(INDENT)
            if (bracey) {
                indentOut.print(" {")
            } else {
                indentOut.print(":")
            }
            printDocstringOn(docstring, indentOut, bracey)
            if (bracey) {
                out.print("}")
            }
        }

    },
    "InterfaceExpr" => def printInterfaceExpr(self, out, priority) as DeepFrozenStamp {
        def stamp := self.getStamp()
        def parents := self.getParents()
        def auditors := self.getAuditors()
        out.print("interface ")
        out.print(self.getName())
        if (stamp != null) {
            out.print(" guards ")
            stamp.subPrintOn(out, priorities["pattern"])
        }
        if (parents.size() > 0) {
            printListOn(" extends ", parents, ", ", "", out, priorities["call"])
        }
        if (auditors.size() > 0) {
            printListOn(" implements ", auditors, ", ", "", out, priorities["call"])
        }
        def indentOut := out.indent(INDENT)
        if (priorities["braceExpr"] <= priority) {
            indentOut.print(" {")
        } else {
            indentOut.print(":")
        }
        printDocstringOn(self.getDocstring(), indentOut, false)
        for m in (self.getMessages()) {
            m.subPrintOn("to", indentOut, priority)
            indentOut.print("\n")
        }
        if (priorities["braceExpr"] <= priority) {
            out.print("}")
        }
    },
    "FunctionInterfaceExpr" => def printFunctionInterfaceExpr(self, out, priority) as DeepFrozenStamp {
        out.print("interface ")
        out.print(self.getName())
        var cuddle := true
        def stamp := self.getStamp()
        def parents := self.getParents()
        def auditors := self.getAuditors()
        if (stamp != null) {
            out.print(" guards ")
            stamp.subPrintOn(out, priorities["pattern"])
            cuddle := false
        }
        if (parents.size() > 0) {
            printListOn(" extends ", parents, ", ", "", out, priorities["call"])
            cuddle := false
        }
        if (auditors.size() > 0) {
            printListOn(" implements ", auditors, ", ", "", out, priorities["call"])
            cuddle := false
        }
        if (!cuddle) {
            out.print(" ")
        }
        def messageDesc := self.getMessageDesc()
        def params := messageDesc.getParams()
        def namedParams := messageDesc.getNamedParams()
        def resultGuard := messageDesc.getResultGuard()
        def docstring := self.getDocstring()
        printListOn("(", params, ", ", "", out, priorities["pattern"])
        if (params.size() > 0 && namedParams.size() > 0) {
            out.print(", ")
        }
        printListOn("", namedParams, ", ", ")", out, priorities["pattern"])

        if (resultGuard != null) {
            out.print(" :")
            resultGuard.subPrintOn(out, priorities["call"])
        }
        if (docstring != null) {
            def bracey := priorities["braceExpr"] <= priority
            def indentOut := out.indent(INDENT)
            if (bracey) {
                indentOut.print(" {")
            } else {
                indentOut.print(":")
            }
            printDocstringOn(docstring, indentOut, bracey)
            if (bracey) {
                out.print("}")
            }
        }
        out.print("\n")
},
    "CatchExpr" => def printCatchExpr(self, out, priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {out.print("try")}, self.getBody(),
                         false, out, priority)
        printExprSuiteOn(fn {
            out.print("catch ")
            self.getPattern().subPrintOn(out, priorities["pattern"])
        }, self.getCatcher(), true, out, priority)
    },
    "FinallyExpr" => def printFinallyEExpr(self, out, priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {out.print("try")}, self.getBody(), false, out, priority)
        printExprSuiteOn(fn {out.print("finally")}, self.getUnwinder(), true, out,
                     priority)
    },
    "TryExpr" => def printTryExpr(self, out, priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {out.print("try")}, self.getBody(), false, out, priority)
        for m in (self.getCatchers()) {
            m.subPrintOn(out, priority)
        }
        if (self.getFinally() != null) {
            printExprSuiteOn(fn {out.print("finally")},
                self.getFinally(), true, out, priority)
        }
    },
    "EscapeExpr" => def printEscapeExpr(self, out, priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {
            out.print("escape ")
            self.getEjectorPattern().subPrintOn(out, priorities["pattern"])
        }, self.getBody(), false, out, priority)
        if (self.getCatchPattern() != null) {
            printExprSuiteOn(fn {
                out.print("catch ")
                self.getCatchPattern().subPrintOn(out, priorities["pattern"])
            }, self.getCatchBody(), true, out, priority)
        }
    },
    "SwitchExpr" => def printSwitchExpr(self, out, priority) as DeepFrozenStamp {
        out.print("switch (")
        self.getSpecimen().subPrintOn(out, priorities["braceExpr"])
        out.print(")")
        def indentOut := out.indent(INDENT)
        if (priorities["braceExpr"] <= priority) {
            indentOut.print(" {")
        } else {
            indentOut.print(":")
        }
        for m in (self.getMatchers()) {
            m.subPrintOn(indentOut, priority)
            indentOut.print("\n")
        }
        if (priorities["braceExpr"] <= priority) {
            out.print("}")
        }
    },
    "WhenExpr" => def printWhenExpr(self, out, priority) as DeepFrozenStamp {
            printListOn("when (", self.getArgs(), ", ", ") ->", out,
                        priorities["braceExpr"])
            def indentOut := out.indent(INDENT)
            if (priorities["braceExpr"] <= priority) {
                indentOut.println(" {")
            } else {
                indentOut.println("")
            }
            self.getBody().subPrintOn(indentOut, priority)
            if (priorities["braceExpr"] <= priority) {
                out.println("")
                out.print("}")
            }
            for c in (self.getCatchers()) {
                c.subPrintOn(out, priority)
            }
            if (self.getFinally() != null) {
                printExprSuiteOn(fn {
                    out.print("finally")
                }, self.getFinally(), true, out, priority)
            }
    },
    "IfExpr" => def printIfExpr(self, out, priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {
            out.print("if (")
            self.getTest().subPrintOn(out, priorities["braceExpr"])
            out.print(")")
            }, self.getThen(), false, out, priority)
        def alt := self.getElse()
        if (alt != null) {
            if (alt.getNodeName() == "IfExpr") {
                if (priorities["braceExpr"] <= priority) {
                    out.print(" ")
                } else {
                    out.println("")
                }
                out.print("else ")
                alt.subPrintOn(out, priority)
            } else {
                printExprSuiteOn(fn {out.print("else")}, alt, true, out, priority)
            }
        }

    },
    "WhileExpr" => def printWhileExpr(self, out, priority) as DeepFrozenStamp {
        printExprSuiteOn(fn {
            out.print("while (")
            self.getTest().subPrintOn(out, priorities["braceExpr"])
            out.print(")")
            }, self.getBody(), false, out, priority)
        def catcher := self.getCatcher()
        if (catcher != null) {
            catcher.subPrintOn(out, priority)
        }
    },
    "HideExpr" => def printHideExpr(self, out, _priority) as DeepFrozenStamp {
        def indentOut := out.indent(INDENT)
        indentOut.println("{")
        self.getBody().subPrintOn(indentOut, priorities["braceExpr"])
        out.println("")
        out.print("}")
    },
    "ValueHoleExpr" => def printValueHoleExpr(self, out, _priority) as DeepFrozenStamp {
        out.print("${expr-hole ")
        out.print(self.getIndex())
        out.print("}")
    },
    "PatternHoleExpr" => def printPatternHoleExpr(self, out, _priority) as DeepFrozenStamp {
        out.print("@{expr-hole ")
        out.print(self.getIndex())
        out.print("}")
    },
    "ValueHolePattern" => def printValueHolePattern(self, out, _priority) as DeepFrozenStamp {
        out.print("${pattern-hole ")
        out.print(self.getIndex())
        out.print("}")
    },
    "PatternHolePattern" => def printPatternHolePattern(self, out, _priority) as DeepFrozenStamp {
        out.print("@{pattern-hole ")
        out.print(self.getIndex())
        out.print("}")
    },
    "FinalPattern" => def printFinalPattern(self, out, priority) as DeepFrozenStamp {
        self.getNoun().subPrintOn(out, priority)
        def guard := self.getGuard()
        if (guard != null) {
            out.print(" :")
            guard.subPrintOn(out, priorities["order"])
        }
    },
    "SlotPattern" => def printSlotPattern(self, out, priority) as DeepFrozenStamp {
        out.print("&")
        self.getNoun().subPrintOn(out, priority)
        def guard := self.getGuard()
        if (guard != null) {
            out.print(" :")
            guard.subPrintOn(out, priorities["order"])
        }
    },
    "BindingPattern" => def printBindingPattern(self, out, priority) as DeepFrozenStamp {
        out.print("&&")
        self.getNoun().subPrintOn(out, priority)
    },
    "VarPattern" => def printVarPattern(self, out, priority) as DeepFrozenStamp {
        out.print("var ")
        self.getNoun().subPrintOn(out, priority)
        def guard := self.getGuard()
        if (guard != null) {
            out.print(" :")
            guard.subPrintOn(out, priorities["order"])
        }
    },
    "BindPattern" => def printBindPattern(self, out, priority) as DeepFrozenStamp {
        out.print("bind ")
        self.getNoun().subPrintOn(out, priority)
        def guard := self.getGuard()
        if (guard != null) {
            out.print(" :")
            guard.subPrintOn(out, priorities["order"])
        }
    },
    "IgnorePattern" => def printIgnorePattern(self, out, _priority) as DeepFrozenStamp {
        out.print("_")
        def guard := self.getGuard()
        if (guard != null) {
            out.print(" :")
            guard.subPrintOn(out, priorities["order"])
        }
    },
    "ListPattern" => def printListPattern(self, out, _priority) as DeepFrozenStamp {
        printListOn("[", self.getPatterns(), ", ", "]", out, priorities["pattern"])
        def tail := self.getTail()
        if (tail != null) {
            out.print(" + ")
            tail.subPrintOn(out, priorities["pattern"])
        }
    },
    "MapPatternAssoc" => def printMapPatternAssoc(self, out, priority) as DeepFrozenStamp {
        def key := self.getKey()
        def value := self.getValue()
        def default := self.getDefault()
        if (key.getNodeName() == "LiteralExpr") {
            key.subPrintOn(out, priority)
        } else {
            out.print("(")
            key.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
        }
        out.print(" => ")
        value.subPrintOn(out, priority)
        if (default != null) {
            out.print(" := (")
            default.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
        }
    },
    "MapPatternImport" => def printMapPatternImport(self, out, priority) as DeepFrozenStamp {
        out.print("=> ")
        self.getPattern().subPrintOn(out, priority)
        def default := self.getDefault()
        if (default != null) {
            out.print(" := (")
            default.subPrintOn(out, "braceExpr")
            out.print(")")
        }
    },
    "MapPattern" => def printMapPattern(self, out, _priority) as DeepFrozenStamp {
        printListOn("[", self.getPatterns(), ", ", "]", out, priorities["pattern"])
        def tail := self.getTail()
        if (tail != null) {
            out.print(" | ")
            tail.subPrintOn(out, priorities["pattern"])
        }
    },
    "NamedParam" => def printNamedParam(self, out, priority) as DeepFrozenStamp {
        def key := self.getKey()
        def default := self.getDefault()
        if (key.getNodeName() == "LiteralExpr") {
            key.subPrintOn(out, priority)
        } else {
            out.print("(")
            key.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
        }
        out.print(" => ")
        self.getPattern().subPrintOn(out, priority)
        if (default != null) {
            out.print(" := (")
            default.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
        }
    },
    "NamedParamImport" => def printNamedParamImport(self, out, priority) as DeepFrozenStamp {
        out.print("=> ")
        self.getPattern().subPrintOn(out, priority)
        def default := self.getDefault()
        if (default != null) {
            out.print(" := (")
            default.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
        }
    },
    "ViaPattern" => def printViaPattern(self, out, priority) as DeepFrozenStamp {
        out.print("via (")
        self.getExpr().subPrintOn(out, priorities["braceExpr"])
        out.print(") ")
        self.getPattern().subPrintOn(out, priority)
    },
    "SuchThatPattern" => def printSuchThatPattern(self, out, priority) as DeepFrozenStamp {
        self.getPattern().subPrintOn(out, priority)
        out.print(" ? (")
        self.getExpr().subPrintOn(out, priorities["braceExpr"])
        out.print(")")
    },
    "SamePattern" => def printSamePattern(self, out, _priority) as DeepFrozenStamp {
        if (self.getDirection()) {
            out.print("==")
        } else {
            out.print("!=")
        }
        self.getValue().subPrintOn(out, priorities["call"])
    },
    "QuasiText" => def printQuasiText(self, out, _priority) as DeepFrozenStamp {
        out.print(self.getText())
    },
    "QuasiExprHole" => def printQuasiExprHole(self, out, priority) as DeepFrozenStamp {
        out.print("$")
        def expr := self.getExpr()
        if (priorities["braceExpr"] < priority) {
            if (expr.getNodeName() == "NounExpr" && isIdentifier(expr.getName())) {
                expr.subPrintOn(out, priority)
                return
            }
            out.print("{")
            expr.subPrintOn(out, priority)
            out.print("}")
        }
    },
    "QuasiPatternHole" => def printQuasiPatternHole(self, out, priority) as DeepFrozenStamp {
        out.print("@")
        def pattern := self.getPattern()
        if (priorities["braceExpr"] < priority) {
            if (pattern.getNodeName() == "FinalPattern") {
                if (pattern.getGuard() == null && isIdentifier(pattern.getNoun().getName())) {
                    pattern.subPrintOn(out, priority)
                    return
                }
            }
            out.print("{")
            pattern.subPrintOn(out, priority)
            out.print("}")
        }
    },
    "QuasiParserExpr" => def printQuasiParserExpr(self, out, _priority) as DeepFrozenStamp {
        quasiPrint(self.getName(), self.getQuasis(), out)
    },
    "QuasiParserPattern" => def printQuasiParserPattern(self, out, _priority) as DeepFrozenStamp {
        quasiPrint(self.getName(), self.getQuasis(), out)
    },
]
