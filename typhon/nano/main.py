from typhon.nano.escapes import elideEscapes
from typhon.nano.mast import saveScripts
from typhon.nano.scopes import layoutScopes, bindNouns
from typhon.nano.slots import recoverSlots
from typhon.nano.structure import refactorStructure

def mainPipeline(expr, safeScopeNames, fqnPrefix, inRepl):
    """
    The bulk of the nanopass pipeline.

    These common operations are desired by everybody.
    """

    from typhon.metrics import globalRecorder
    with globalRecorder().context(u"nanopass"):
        ss = saveScripts(expr)
        slotted = recoverSlots(ss)
        ll, outerNames, topLocalNames, localSize = layoutScopes(slotted,
                                                                safeScopeNames,
                                                                fqnPrefix, inRepl)
        bound = bindNouns(ll)
        ast = elideEscapes(bound)
        ast = refactorStructure(ast)
        return ast, outerNames, topLocalNames, localSize
