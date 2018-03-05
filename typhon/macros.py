from ast import (Assign, Subscript, Attribute, List, Tuple, Name, Import,
                 ImportFrom, FunctionDef, ClassDef, ListComp, For, ExceptHandler)

from macropy.core.macros import Macros, Walker
from macropy.core.quotes import q, u, name

macros = Macros()


def walkLvalues(subt, ctx, set_ctx, collect):
    if type(subt) in (Subscript, Attribute):
        # no names are bound here, keep going
        ctx['state'] = None
    elif type(subt) is Name:
        if subt.id in ctx['freeNames']:
            raise NameError("Can't really rebind outer name %s "
                            "inside a when-block" % (subt.id,))
        ctx['state'] = None
        collect(subt.id)
    elif type(subt) in (List, Tuple):
        newCtx = ctx.copy()
        newCtx['state'] = 'lvalue'
        set_ctx(newCtx)


@Walker
def collectModuleGlobals(tree, ctx, set_ctx, collect, stop, **kw):
    if ctx['state'] == 'lvalue':
        walkLvalues(tree, ctx, set_ctx, collect)
        return
    if type(tree) in (Import, ImportFrom):
        for n in tree.names:
            collect(n.asname or n.name.split('.')[0])
    if type(tree) in (FunctionDef, ClassDef):
        collect(tree.name)
        return stop()
    if type(tree) is Assign:
        walkLvalues(tree.targets[0], ctx, set_ctx, collect)
    if type(tree) is ListComp:
        for g in tree.generators:
            walkLvalues(g.target, ctx, set_ctx, collect)
    if type(tree) is For:
        walkLvalues(tree.target, ctx, set_ctx, collect)
    if type(tree) is ExceptHandler:
        walkLvalues(tree.name, ctx, set_ctx, collect)


@Walker
def rewriteFreeNames(tree, ctx, set_ctx, **kw):

    if type(tree) is Assign:
        walkLvalues(tree.targets[0], ctx, set_ctx,
                    ctx['boundNames'].add)
    if ctx['state'] == 'lvalue':
        walkLvalues(tree, ctx, set_ctx,
                    ctx['boundNames'].add)
    elif type(tree) is Name:
        if (tree.id not in ctx['boundNames'] and
                tree.id not in ctx['moduleGlobals'] and
                tree.id not in __builtins__.__dict__ and
                tree.id != ctx['resultName']):
            if tree.id not in ctx['freeNames']:
                ctx['freeNames'][tree.id] = ctx['gen_sym']()
            return Attribute(ctx['selfName'], ctx['freeNames'][tree.id])


@macros.block
def when(tree, target, gen_sym, **kw):
    _, moduleGlobals = collectModuleGlobals.recurse_collect(tree,
                                                            {'state': None})
    ctx = {
        'state': None,
        'boundNames': set(),
        'moduleGlobals': moduleGlobals,
        'freeNames': set(),
        'selfName': gen_sym(),
        'resultName': target.id,
        'gen_sym': gen_sym
    }


@macros.block
def catch(tree, target, **kw):
    return tree
