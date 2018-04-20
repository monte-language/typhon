import __builtin__
from ast import (Assign, Expr, Subscript, Attribute, List, Tuple, Name, Import,
                 ImportFrom, FunctionDef, ClassDef, ListComp, For, Num, If, Eq,
                 TryExcept, ExceptHandler, Call, Store, Load, Compare, alias,
                 arguments, copy_location, fix_missing_locations, Str, Raise)
from collections import namedtuple
import copy
from macropy.core.macros import (Macros, Walker, injected_vars,
                                 post_processing)
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
            if (tree.id not in ctx['freeNames'] and
                    tree.id not in ctx['boundNames']):
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


Op = namedtuple('Op', ['expr', 'successIndex', 'failIndex',
                       'successName', 'failName'])


def buildOperationsTable(lines):
    """
    Dissects control and data flow to prepare for generating callbacks.
    Returns a list of tuples, in reverse order of execution, containing:
     * a single expression
     * Relative address (or None) for the next operation on success
     * Relative address (or None) for the next operation on failure
     * Name to bind (or None) on success
     * Name to bind (or None) on failure
    """
    flowList = []

    def collectLine(line, failTarget, failName, successTarget):
        if isinstance(line, Assign):
            assert isinstance(line.targets[0], Name), (
                "assignment in io blocks must be to single names")
            flowList.append(Op(line.value, successTarget if flowList else None,
                               failTarget, line.targets[0].id, failName))
        elif isinstance(line, Expr):
            flowList.append(Op(line.value, successTarget if flowList else None,
                               failTarget, None, failName))
        elif isinstance(line, TryExcept):
            assert len(line.handlers) == 1, (
                "try statements in io blocks must "
                "have exactly one except block")
            # jump target at end of else
            exitPoint = len(flowList)
            if line.orelse:
                # process else block in reverse order
                collectLine(line.orelse[-1], failTarget, failName,
                            successTarget)
                for elseline in reversed(line.orelse[:-1]):
                    collectLine(elseline, failTarget, failName, -1)
            # jump target at beginning of else
            elsePoint = len(flowList)
            exName = line.handlers[0].name.id
            excSuccessTarget = (exitPoint - len(flowList) + successTarget
                                if exitPoint else None)
            excFailTarget = (exitPoint - len(flowList) + failTarget
                             if failTarget else None)
            # process except block in reverse order
            collectLine(line.handlers[0].body[-1], excFailTarget, failName,
                        excSuccessTarget)
            for excline in reversed(line.handlers[0].body[:-1]):
                excFailTarget = (exitPoint - len(flowList) + failTarget
                                 if failTarget else None)
                collectLine(excline, excFailTarget, failName, -1)
            #jump target at beginning of catch block
            catchPoint = len(flowList)
            if line.orelse:
                # jump into else when done
                trySuccessTarget = elsePoint - len(flowList) - 1
            else:
                # jump to end of except when done
                trySuccessTarget = (exitPoint - len(flowList) + successTarget
                                    if exitPoint else None)
            # process try block in reverse order
            collectLine(line.body[-1], -1, exName, trySuccessTarget)
            for tryline in reversed(line.body[:-1]):
                collectLine(tryline, catchPoint - len(flowList) - 1,
                            exName, -1)
        else:
            raise SyntaxError("Expected assign statement, call, or try/except "
                              "statement in io block, not " +
                              line.__class__.__name__)

    for line in reversed(lines):
        collectLine(line, None, None, -1)
    return flowList


CallbackInfo = namedtuple(
    'CallbackInfo', ['base', 'successName', 'successExpr', 'successIndex',
                     'failName', 'failExpr', 'failIndex'])


def opsToCallbacks(originalOpList):
    """
    Convert a list of ops into callbacks.

    Returns a dict of names bound to initial constants and a list, in execution
    order, containing tuples of:
     * Base class expression for callback class
     * Name to bind (or None) for success value received
     * Expression to execute upon success
     * Callback number to pass control to on success
     * Name to bind (or None) for error value received
     * Expression to execute upon failure
     * Callback number to pass control to on error
    """
    ops = []
    initialState = {}
    # collect initial constants and remove from ops list
    while True:
        oo = originalOpList[-1]
        if isinstance(oo.expr, (Num, Str)) and oo.successName:
            initialState[oo.successName] = oo.expr
            del originalOpList[-1]
        else:
            break

    # Convert relative addresses to absolute addresses

    ops = [op._replace(successIndex=i - op.successIndex
                       if op.successIndex is not None else None,
                       failIndex=i - op.failIndex
                       if op.failIndex is not None else None)
           for i, op in enumerate(reversed(originalOpList))]
    successNeedsPatching = {}
    failNeedsPatching = {}
    callbacks = []
    for expr, successIndex, failIndex, successName, failName in ops:
        successExpr = None
        failExpr = None
        if successIndex:
            # Look at successor op and put its expr in this callback
            successExpr = ops[successIndex].expr
            if ops[successIndex].successIndex or ops[successIndex].failIndex:
                # Fix up this callback later with address of callback following
                # this expr (if any)
                successNeedsPatching.setdefault(successExpr, set()).add(
                    len(callbacks))
        if failIndex:
            failExpr = ops[failIndex].expr
            if ops[failIndex].successIndex or ops[failIndex].failIndex:
                failNeedsPatching.setdefault(failExpr, set()).add(
                    len(callbacks))
        if successExpr or failExpr:
            callbacks.append(CallbackInfo(
                Attribute(expr.func, "callbackType", Load()),
                successName, successExpr, None,
                failName, failExpr, None))

        successPatchTargets = successNeedsPatching.get(expr, ())
        for i in successPatchTargets:
            callbacks[i] = callbacks[i]._replace(
                successIndex=len(callbacks) - 1)
        failPatchTargets = failNeedsPatching.get(expr, ())
        for i in failPatchTargets:
            callbacks[i] = callbacks[i]._replace(
                failIndex=len(callbacks) - 1)
    return initialState, callbacks


@macros.block
def io(tree, target, gen_sym, moduleGlobals, importNames, toEmit, **kw):
    """
    RPython doesn't allow many things that are convenient in Python, such as
    nested functions, and furthermore its type checker is very restrictive.
    This makes callback-based async IO rather verbose to implement.  To cope
    with this, Typhon uses MacroPy to provide a small sublanguage for chaining
    IO actions together.  (If you're familiar with Haskell, it's similar in
    spirit to to 'do' notation.)

    The basic idea is that inside a block started by `with io:`, execution does
    not proceed in a straight line as it would with normal Python code.
    Instead, each statement is turned into a callback that gets invoked when
    the operation from the previous statement is complete.  The only statements
    allowed in an `io` block are:
      * Try/except/else (with a single except block)
      * literals and calls invoking IO actions
      * Assignment to a single name

    IO blocks effectively have their own scope.  Assigning to names within them
    will not modify names defined outside them.  Typically they are used by
    creating a Monte promise to represent the final result of the sequence of
    IO actions, and invoking the associated resolver when the IO actions are
    complete.

    The use of try/except is similarly restricted; `except` blocks are
    unconditionally invoked when an action in the `try` block signals failure,
    rather than matching on exception type.  Therefore the idiom is to use
    `except object as err:` since the macro implementation ignores the type
    normally used for matching.
    """

    None_ = Name("None", Load())
    stateClassName = gen_sym("State")
    FutureCtx_ = importNames["FutureCtx"]
    OK_ = importNames["OK"]
    ERR_ = importNames["ERR"]
    self_ = gen_sym("self")
    state = gen_sym("state")
    result = gen_sym("result")
    status = gen_sym("status")
    successValue = gen_sym("successValue")
    failValue = gen_sym("failureValue")
    freeNames = []
    boundNames = {}

    if not toEmit:
        toEmit.append()


    ops = buildOperationsTable(tree)
    initialState, callbacks = opsToCallbacks(ops)
    boundNames.update(initialState)
    callbackNames = [gen_sym("ioCallback") for _ in callbacks]
    for callbackName, cb in zip(callbackNames, callbacks):
        if cb.successName:
            successArm = [Assign([Attribute(Name(state, Load()),
                                            cb.successName, Store())],
                                 Name(successValue, Load()))]
            boundNames.setdefault(cb.successName, None_)
        else:
            successArm = []
        if cb.successExpr:
            if cb.successIndex is not None:
                successCb = Name(callbackNames[cb.successIndex], Load())
            else:
                successCb = None_
            successArm.append(Expr(Call(Attribute(
                rewriteAsCallback(copy.deepcopy(cb.successExpr), state,
                                  moduleGlobals, boundNames, freeNames),
                "run", Load()),
                                        [Name(state, Load()),
                                         successCb], [],
                                        None, None)))
        if cb.failExpr:
            if cb.failName:
                failArm = [Assign([Attribute(Name(state, Load()),
                                             cb.failName, Store())],
                                  Name(failValue, Load()))]
                boundNames.setdefault(cb.failName, None_)
            else:
                failArm = []
            if cb.failIndex is not None:
                failCb = Name(callbackNames[cb.failIndex], Load())
            else:
                failCb = None_
            failArm.append(Expr(Call(Attribute(
                rewriteAsCallback(copy.deepcopy(cb.failExpr), state,
                                  moduleGlobals, boundNames,
                                  freeNames),
                "run", Load()),
                                     [Name(state, Load()),
                                      failCb], [],
                                     None, None)))
        finalThrow = Raise(Call(Name('RuntimeError', Load()),
                                [Str('unexpected failure in io '
                                     'callback')],
                                [], None, None), None, None)
        failStmt = If(Compare(Name(status, Load()), [Eq()],
                              [Name(ERR_, Load())]),
                      failArm,
                      [finalThrow]) if cb.failExpr else finalThrow
        successStmt = If(Compare(Name(status, Load()), [Eq()],
                                 [Name(OK_, Load())]),
                         successArm,
                         [failStmt]) if cb.successExpr else failStmt
        callbackBody = [Assign([Tuple([Name(status, Store()),
                                       Name(successValue, Store()),
                                       Name(failValue, Store())], Store())],
                               Name(result, Load())),
                        successStmt]

        callbackClassName = callbackName + "_Class"
        callbackMethod = FunctionDef("do",
                                     arguments(
                                         [Name(self_, Store()),
                                          Name(state, Store()),
                                          Name(result, Store())],
                                         None, None, []),
                                     callbackBody,
                                     [])
        callbackClass = ClassDef(callbackClassName,
                                 [cb.base],
                                 [callbackMethod], [])
        toEmit.append(callbackClass)
        callbackInstance = Assign([Name(callbackName, Store())],
                                  Call(Name(callbackClassName, Load()), [], [],
                                       None, None))
        toEmit.append(callbackInstance)


    createState = Call(Name(stateClassName, Load()),
                       [Name(n, Load()) for n in freeNames], [], None, None)
    topLine = copy_location(Expr(
        Call(Attribute(ops[-1].expr, "run", Load()),
             [createState, Name(callbackNames[0], Load())],
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
    toEmit.append(stateClass)
    return [fix_missing_locations(topLine)]

@injected_vars.append
def importNames(tree, src, gen_sym, **kw):
    return {
        "FutureCtx": gen_sym("FutureCtx"),
        "OK": gen_sym("OK"),
        "ERR": gen_sym("ERR")
    }

@injected_vars.append
def toEmit(tree, src, importNames, **kw):
    return [ImportFrom("typhon.futures",
                       [alias(k, v) for k, v in importNames.items()],
                       0)]


@injected_vars.append
def moduleGlobals(tree, src, **kw):
    return collectModuleGlobals.recurse_collect(tree, state=None)[1]


@post_processing.append
def emit(tree, src, toEmit, **kw):
    tree.body.extend([fix_missing_locations(n) for n in toEmit])
    return tree
