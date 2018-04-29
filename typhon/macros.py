import __builtin__
from ast import (Assign, Expr, Subscript, Attribute, List, Tuple, Name, Import,
                 ImportFrom, FunctionDef, ClassDef, ListComp, For, Num, If, Eq,
                 TryExcept, ExceptHandler, Call, Store, Load, Compare, alias,
                 arguments, copy_location, fix_missing_locations, Str, Raise)
from collections import namedtuple
import copy
from macropy.core.macros import (Macros, Walker, injected_vars,
                                 post_processing, unparse)
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


def rewriteAsCallback(expr, cbName, state, globalNames, boundNames, freeNames):
    """
    Walk over the expr looking for non-global names. Rewrite them to be state
    lookups. Collect free names.
    """
    ctx = {'boundNames': boundNames,
           'selfName': state,
           'moduleGlobals': globalNames,
           'freeNames': freeNames}
    newExpr, _ = rewriteFreeNames.recurse_collect(expr, **ctx)
    return Expr(Call(Attribute(newExpr, "run", Load()),
                     [Name(state, Load()),
                      Name(cbName or "None", Load())], [],
                     None, None))


Op = namedtuple('Op', ['expr', 'successOp', 'failOp',
                       'successName', 'failName'])
IfOp = namedtuple('IfOp', ['testExpr', 'consqOp', 'altOp', 'failOp',
                           'failName'])


def buildOperationsDAG(lines):
    """
    Dissects control and data flow to prepare for generating callbacks.
    Returns a list of tuples, in reverse order of execution, containing:
     * a single expression
     * next operation on success
     * next operation on failure
     * Name to bind (or None) on success
     * Name to bind (or None) on failure
    """
    flowList = []

    def collectLine(line, failTarget, failName, successTarget):
        if isinstance(line, Assign):
            assert isinstance(line.targets[0], Name), (
                "assignment in io blocks must be to single names")
            flowList.append(Op(line.value, successTarget,
                               failTarget, line.targets[0].id, failName))
        elif isinstance(line, Expr):
            flowList.append(Op(line.value, successTarget,
                               failTarget, None, failName))
        elif isinstance(line, If):
            altTarget = successTarget
            if line.orelse:
                # process else block in reverse order
                collectLine(line.orelse[-1], failTarget, failName,
                            successTarget)
                for elseline in reversed(line.orelse[:-1]):
                    collectLine(elseline, failTarget, failName, flowList[-1])
                altTarget = flowList[-1]
            collectLine(line.body[-1], failTarget, failName,
                        successTarget)
            for bodyLine in reversed(line.body[:-1]):
                collectLine(bodyLine, failTarget, failName, flowList[-1])
            flowList.append(IfOp(
                line.test, flowList[-1], altTarget, failName, failTarget))
        elif isinstance(line, TryExcept):
            assert len(line.handlers) == 1, (
                "try statements in io blocks must "
                "have exactly one except block")
            if line.orelse:
                # process else block in reverse order
                collectLine(line.orelse[-1], failTarget, failName,
                            successTarget)
                for elseline in reversed(line.orelse[:-1]):
                    collectLine(elseline, failTarget, failName, flowList[-1])
                # jump target at beginning of else
                elseTarget = flowList[-1]
            else:
                elseTarget = successTarget
            exName = line.handlers[0].name.id
            # process except block in reverse order
            collectLine(line.handlers[0].body[-1], failTarget, failName,
                        successTarget)
            for excline in reversed(line.handlers[0].body[:-1]):
                collectLine(excline, failTarget, failName, flowList[-1])
            catchTarget = flowList[-1]
            # process try block in reverse order
            collectLine(line.body[-1], catchTarget, exName, elseTarget)
            for tryline in reversed(line.body[:-1]):
                collectLine(tryline, catchTarget,
                            exName, flowList[-1])
        else:
            raise SyntaxError("Expected assign statement, call, or try/except "
                              "statement in io block, not " +
                              line.__class__.__name__)

    for line in reversed(lines):
        collectLine(line, None, None, flowList[-1] if flowList else None)
    return flowList


class CallbackInfo(object):
    """
    Not a namedtuple because callback links need to be patched after creation.
    """
    def __init__(self, base, successName, successExpr, failName, failExpr):
        self.base = base
        self.successName = successName
        self.successExpr = successExpr
        self.failName = failName
        self.failExpr = failExpr
        self.successCB = None
        self.failCB = None
        self.functionName = None

    def patchTarget(self, patchTable):
        """
        Hook up a callback to an expr feeding it.
        """
        self.successCB = patchTable.get(self.successExpr)
        self.failCB = patchTable.get(self.failExpr)


class IfCallbackInfo(object):
    def __init__(self, base, successName, testExpr, consqExpr, altExpr,
                 failName, failExpr):
        self.base = base
        self.successName = successName
        self.testExpr = testExpr
        self.consqExpr = consqExpr
        self.altExpr = altExpr
        self.failName = failName
        self.failExpr = failExpr
        self.consqCB = None
        self.altCB = None
        self.failCB = None
        self.functionName = None

    def patchTarget(self, patchTable):
        """
        Hook up a callback to an expr feeding it.
        """
        self.consqCB = patchTable.get(self.consqExpr)
        self.altCB = patchTable.get(self.altExpr)
        self.failCB = patchTable.get(self.failExpr)


def opsToCallbacks(ops):
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
    initialState = {}
    # collect initial constants and remove from ops list
    while True:
        oo = ops[-1]
        if isinstance(oo.expr, (Num, Str, Name)) and oo.successName:
            initialState[oo.successName] = oo.expr
            del ops[-1]
        else:
            break

    ops = ops[::-1]
    callbacks = []
    patchTable = {}
    for op in ops:
        if isinstance(op, IfOp):
            # already processed this
            continue
        expr, successOp, failOp, successName, failName = op
        if not (successOp or failOp):
            continue
        if isinstance(successOp, IfOp):
            newCB = IfCallbackInfo(
                Attribute(expr.func, "callbackType", Load()),
                successName, successOp.testExpr,
                successOp.consqOp.expr,
                successOp.altOp.expr,
                failName, successOp.failOp and successOp.failOp.expr)
        else:
            newCB = CallbackInfo(Attribute(expr.func, "callbackType", Load()),
                                 successName, successOp and successOp.expr,
                                 failName, failOp and failOp.expr)
        callbacks.append(newCB)
        patchTable[expr] = newCB

    for cb in callbacks:
        cb.patchTarget(patchTable)

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

    ops = buildOperationsDAG(tree)
    initialState, callbacks = opsToCallbacks(ops)
    boundNames.update(initialState)
    for cb in callbacks:
        cb.functionName = gen_sym("ioCallback")

    def bindName(name, value):
        if name:
            boundNames.setdefault(name, None_)
            return [Assign([Attribute(Name(state, Load()),
                                      name, Store())],
                           Name(value, Load()))]
        else:
            return []

    def exprAsCallback(expr, nextCB):
        return rewriteAsCallback(copy.deepcopy(expr),
                                 nextCB and nextCB.functionName, state,
                                 moduleGlobals, boundNames,
                                 freeNames)

    for cb in callbacks:
        if isinstance(cb, IfCallbackInfo):
            successArm = bindName(cb.successName, successValue)
            ctx = {'boundNames': boundNames, 'selfName': state,
                   'moduleGlobals': moduleGlobals, 'freeNames': freeNames}
            newTest, _ = rewriteFreeNames.recurse_collect(cb.testExpr, **ctx)
            successArm.append(If(newTest,
                                 [exprAsCallback(cb.consqExpr, cb.consqCB)],
                                 [exprAsCallback(cb.altExpr, cb.altCB)]))
        else:
            successArm = bindName(cb.successName, successValue)
            if cb.successExpr:
                successArm.append(exprAsCallback(cb.successExpr, cb.successCB))
        failArm = bindName(cb.failName, failValue)
        if cb.failExpr:
            failArm.append(exprAsCallback(cb.failExpr, cb.failCB))
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
                         [failStmt]) if successArm else failStmt
        callbackBody = [Assign([Tuple([Name(status, Store()),
                                       Name(successValue, Store()),
                                       Name(failValue, Store())], Store())],
                               Name(result, Load())),
                        successStmt]

        callbackClassName = cb.functionName + "_Class"
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
        callbackInstance = Assign([Name(cb.functionName, Store())],
                                  Call(Name(callbackClassName, Load()), [], [],
                                       None, None))
        toEmit.append(callbackInstance)

    createState = Call(Name(stateClassName, Load()),
                       [Name(n, Load()) for n in freeNames] +
                       boundNames.values(), [], None, None)
    topLine = copy_location(Expr(
        Call(Attribute(ops[-1].expr, "run", Load()),
             [createState, Name(callbacks[0].functionName
                                if callbacks else "None", Load())],
             [], None, None)),
        tree[0])
    stateInit = FunctionDef(
        "__init__",
        arguments([Name(self_, Store())] +
                  [Name(n, Load()) for n in freeNames + boundNames.keys()], None, None, []),
        ([Assign([Attribute(Name(self_, Load()), n, Store())], Name(n, Load()))
         for n in freeNames] +
         [Assign([Attribute(Name(self_, Load()), k, Store())], Name(k, Load()))
          for k in boundNames.keys()]) or [Expr(None_)],
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
