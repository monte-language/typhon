import __builtin__
from ast import (Assign, Expr, Subscript, Attribute, List, Tuple, Name, Import,
                 ImportFrom, FunctionDef, ClassDef, ListComp, For, Num,
                 ExceptHandler, Call, Store, Load, alias, arguments,
                 copy_location, fix_missing_locations)
import copy
from macropy.core.macros import Macros, Walker, injected_vars, post_processing
from typhon.futures import OK
macros = Macros()


def walkLvalues(subt, set_ctx, collect, state):
    if type(subt) in (Subscript, Attribute):
        # no names are bound here, keep going
        set_ctx(state=None)
    elif type(subt) is Name:
        set_ctx(state=None)
        collect(subt.id)
    elif type(subt) in (List, Tuple):
        set_ctx(state='lvalue')


@Walker
def collectModuleGlobals(tree, set_ctx, collect, stop, state, **kw):
    if state == 'lvalue':
        walkLvalues(tree, set_ctx, collect, state)
        return
    if type(tree) in (Import, ImportFrom):
        for n in tree.names:
            collect(n.asname or n.name.split('.')[0])
    if type(tree) in (FunctionDef, ClassDef):
        collect(tree.name)
        return stop()
    if type(tree) is Assign:
        walkLvalues(tree.targets[0], set_ctx, collect, state)
    if type(tree) is ListComp:
        for g in tree.generators:
            walkLvalues(g.target, set_ctx, collect, state)
    if type(tree) is For:
        walkLvalues(tree.target, set_ctx, collect, state)
    if type(tree) is ExceptHandler:
        walkLvalues(tree.name, set_ctx, collect, state)


@Walker
def rewriteFreeNames(tree, stop, **ctx):
    if type(tree) is Name:
        if (tree.id not in ctx['moduleGlobals'] and
                tree.id not in __builtin__.__dict__):
            if tree.id not in ctx['freeNames'] and tree.id not in ctx['boundNames']:
                ctx['freeNames'].append(tree.id)
            stop()
            return Attribute(Name(ctx['selfName'], Load()), tree.id, tree.ctx)


def rewriteAsCallback(expr, state, globalNames, boundNames, freeNames):
    """
    Walk over the expr looking for non-global names. Rewrite them to be state
    lookups. Collect free names.
    """
    ctx = {'boundNames': boundNames,
           'selfName': state,
           'moduleGlobals': globalNames,
           'freeNames': freeNames}
    _, newExpr = rewriteFreeNames.recurse_collect(expr, **ctx)
    return expr


@macros.block
def io(tree, target, gen_sym, moduleGlobals, toEmit, **kw):
    firstCallback = nextCallback = gen_sym("iostart_callback")
    stateClassName = gen_sym("State")
    FutureCtx_ = gen_sym("FutureCtx")
    OK_ = gen_sym("Ok")
    Err_ = gen_sym("Err")
    freeNames = []
    boundNames = {}
    targetName = None
    topLine = None
    None_ = Name("None", Load())
    nextCallbackBase = Name("object", Load())
    toEmit.append(ImportFrom("typhon.futures", [alias("FutureCtx", FutureCtx_),
                                                alias("Ok", OK_),
                                                alias("Err", Err_)],
                             0))
    for i, line in enumerate(tree):
        def emit(node):
            toEmit.append(copy_location(node, line))
        assert isinstance(line, (Assign, Expr)), "Only assignments and calls allowed in io block"
        expr = line.value
        if isinstance(expr, Num) and isinstance(line, Assign):
            boundNames[line.targets[0].id] = expr
            continue
        assert isinstance(expr, Call), "io block line must be a call to an io operation"
        self_ = gen_sym("self")
        state = gen_sym("state")
        result = gen_sym("result")
        if targetName:
            status = gen_sym("status")
            err = gen_sym("err")
            collectResult = [Assign([Tuple([Name(status, Store()),
                                            Name(targetName, Store()),
                                            Name(err, Store())], Store())],
                                    Name(result, Load())),
                             Assign([Attribute(Name(state, Load()),
                                               targetName, Store())],
                                    Name(targetName, Load()))]
            if targetName not in boundNames:
                boundNames[targetName] = None_
        else:
            collectResult = []
        opname = expr.func
        opnameStr = opname.id if isinstance(opname, Name) else None
        callbackName = nextCallback
        callbackClassName = callbackName + "_Class"
        callbackBase = nextCallbackBase
        if (i + 1) == len(tree):
            nextCallback = "None"
        else:
            nextCallback = gen_sym(opnameStr or "io")
            nextCallbackBase = Attribute(expr.func, "callbackType", Load()) #if  else Name("object", Load())

        callbackBody = Expr(Call(Attribute(
            rewriteAsCallback(copy.deepcopy(expr), state, moduleGlobals,
                              boundNames, freeNames), "run", Load()),
                            [Name(state, Load()), Name(nextCallback, Load())], [], None, None))
        callbackMethod = FunctionDef("do",
                                     arguments(
                                         [Name(self_, Store()),
                                          Name(state, Store()),
                                          Name(result, Store())],
                                         None, None, []),
                                     collectResult + [callbackBody],
                                     [])
        callbackClass = ClassDef(callbackClassName,
                                 [callbackBase],
                                 [callbackMethod], [])
        emit(callbackClass)
        callbackInstance = Assign([Name(callbackName, Store())],
                                  Call(Name(callbackClassName, Load()), [], [], None, None))
        emit(callbackInstance)
        if isinstance(line, Assign):
            # XXX could support tuple assignment here if we wanted
            assert isinstance(line.targets[0], Name), ("assignment in io blocks"
                                                       " must be to single names")
            targetName = line.targets[0].id

        else:
            targetName = None
    createState = Call(Name(stateClassName, Load()),
                       [Name(n, Load()) for n in freeNames], [], None, None)
    topLine = copy_location(Expr(
        Call(Attribute(Name(firstCallback, Load()), "do", Load()),
             [createState, Tuple([Name(OK_, Load()), None_, None_], Load())],
             [], None, None)),
        tree[0])
    stateInit = FunctionDef(
        "__init__",
        arguments([Name(self_, Store())] + [Name(n, Load()) for n in freeNames], None, None, []),
        [Assign([Attribute(Name(self_, Load()), n, Store())], Name(n, Load())) for n in freeNames] +
        [Assign([Attribute(Name(self_, Load()), k, Store())], v)
         for k, v in boundNames.items()],
        [])
    stateClass = ClassDef(stateClassName,
                          [Name(FutureCtx_, Load())],
                          [stateInit], [])
    emit(stateClass)
    return [fix_missing_locations(topLine)]


@injected_vars.append
def toEmit(tree, src, **kw):
    return []


@injected_vars.append
def moduleGlobals(tree, src, **kw):
    return collectModuleGlobals.recurse_collect(tree, state=None)[1]


@post_processing.append
def emit(tree, src, toEmit, **kw):
    tree.body.extend([fix_missing_locations(n) for n in toEmit])
    return tree
