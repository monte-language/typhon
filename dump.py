#!/usr/bin/env python

import sys
from typhon.errors import LoadFailed, UserException
from typhon.load.nano import InvalidMAST, loadMASTBytes
from typhon.nano.main import mainPipeline
from typhon.nano.structure import prettifyStructure
from typhon.nodes import InvalidAST


def dumpLines(s):
    for line in s.encode("utf-8").split("\n"):
        print line.rstrip()

safeScopeNames = [
    u"null", u"any", u"Any", u"Infinity", u"NaN", u"false", u"true",
    u"Binding", u"DeepFrozen", u"Near", u"Same", u"Selfless", u"SubrangeGuard", u"M",
    u"Ref", u"__auditedBy", u"__equalizer", u"__loop", u"__makeDouble", u"__makeInt",
    u"__makeList", u"__makeMap", u"__makeSourceSpan",
    u"__slotToBinding", u"_auditedBy", u"_equalizer", u"_loop", u"_makeBytes",
    u"_makeDouble", u"_makeFinalSlot", u"_makeInt", u"_makeList", u"_makeMap",
    u"_makeSourceSpan", u"_makeVarSlot", u"_slotToBinding",
    u"throw", u"traceln", u"Comparison", u"Comparable", u"WellOrdered",
    u"Void", u"Bool", u"Bytes", u"Char", u"Double", u"Int", u"Str",
    u"_makeOrderedSpace", u"Empty", u"List", u"Map", u"NullOk", u"Pair",
    u"Set", u"Vow", u"_mapEmpty", u"_mapExtract", u"_accumulateList",
    u"_accumulateMap", u"_booleanFlow", u"_iterForever",
    u"_switchFailed", u"_makeVerbFacet", u"_comparer", u"_suchThat",
    u"_matchSame", u"_bind", u"_quasiMatcher", u"_splitList", u"import",
    u"typhonEval", u"makeLazySlot", u"astBuilder", u"simple__quasiParser",
    u"_makeMessageDesc", u"_makeParamDesc",
    u"_makeProtocolDesc", u"__makeMessageDesc", u"__makeParamDesc",
    u"__makeProtocolDesc", u"b__quasiParser", u"m__quasiParser", u"b``",
    u"m``", u"``", u"eval", u"Transparent", u"safeScope",
    u"promiseAllFulfilled", u"FinalSlot", u"VarSlot"]


def entryPoint(argv):
    path = argv[1]
    try:
        expr = loadMASTBytes(open(path, "rb").read(), path, noisy=False)
    except InvalidAST:
        print "Invalid AST"
        return 1
    except InvalidMAST:
        print "Invalid MAST"
        return 1
    try:
        ast, _, _, _ = mainPipeline(expr, safeScopeNames,
                path.decode("utf-8"), False)
    except LoadFailed as lf:
        print "RPython-level exception; invalid AST"
        print lf
        return 1
    except UserException as ue:
        print "Monte-level exception while compiling:"
        print ue.formatError()
        return 1
    try:
        pretty = prettifyStructure(ast)
        dumpLines(pretty)
    except UserException as ue:
        print "Monte-level exception while pretty-printing:"
        print ue.formatError()
        return 1
    return 0


def target(driver, *args):
    driver.exe_name = "mt-dump-mast"
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
