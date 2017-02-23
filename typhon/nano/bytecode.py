"""
Some sort of hybrid bytecode thing.
"""

from typhon.atoms import getAtom
from typhon.nanopass import makeIR
from typhon.nano.mix import MixIR
from typhon.objects.constants import NullObject
from typhon.objects.guards import anyGuard
from typhon.objects.user import GuardInfo

COERCE_2 = getAtom(u"coerce", 2)
CONTAINS_1 = getAtom(u"contains", 1)
FETCH_2 = getAtom(u"fetch", 2)
GET_1 = getAtom(u"get", 1)
RUN_2 = getAtom(u"run", 2)
WITH_2 = getAtom(u"with", 2)

def makeBytecode(expr):
    compiler = MakeBytecode()
    expr = compiler.visitExpr(expr)
    return expr, compiler.popFrame()

BytecodeIR = makeIR("Bytecode",
    ["Object", "Exception"],
    {
        "Expr": {
            "BytecodeExpr": [("insts", None)],
            "SeqExpr": [("exprs", "Expr*")],
            "EscapeOnlyExpr": [("body", "Expr")],
            "EscapeExpr": [("ejBody", "Expr"), ("catchBody", "Expr")],
            "FinallyExpr": [("body", "Expr"), ("atLast", "Expr")],
            "IfExpr": [("test", "Expr"), ("cons", "Expr"), ("alt", "Expr")],
            "TryExpr": [("body", "Expr"), ("catchBody", "Expr")],
        },
        "Method": {
            "MethodExpr": [("doc", None), ("verb", None), ("frame", None),
                           ("expr", "Expr"), ("localSize", None)],
        },
        "Matcher": {
            "MatcherExpr": [("frame", None), ("expr", "Expr"),
                            ("localSize", None)],
        },
        "Script": {
            "ScriptExpr": [("name", None), ("doc", None), ("mast", None),
                           ("layout", None), ("stamps", "Object*"),
                           ("methods", "Method*"), ("matchers", "Matcher*")],
        },
    }
)

(
    POP, DUP, SWAP, NROT, OVER,
    LIVE, EX, LOCAL, FRAME,
    BINDFB, BINDFS, BINDN, BINDVB, BINDVS,
    CALL, CALLMAP,
    MAKEMAP,
    MATCHLIST,
    AUDIT,
    MAKEOBJECT, MAKESTAMPEDOBJECT, TIEKNOT,
) = range(22)

def concatBytecode(left, right):
    rv = left[:]
    for t in right:
        inst, idx = t
        # LIVE POP ->
        if inst == POP:
            top, _ = rv[-1]
            if top in (LIVE, EX, LOCAL, FRAME):
                rv.pop()
            elif top == DUP:
                rv.pop()
        else:
            rv.append(t)
    return rv

# Patch in a class with richer functionality.
class BytecodeExpr(BytecodeIR.BytecodeExpr):

    def add(self, insts):
        return BytecodeExpr(concatBytecode(self.insts, insts))
BytecodeIR.BytecodeExpr = BytecodeExpr

def add(self, insts):
    return BytecodeIR.SeqExpr([self, BytecodeExpr(insts)])
def addExpr(self, expr):
    if isinstance(expr, BytecodeExpr):
        return self.add(expr.insts)
    else:
        return BytecodeIR.SeqExpr(self, expr)
BytecodeIR.Expr.add = add
BytecodeIR.Expr.addExpr = addExpr


class StaticFrame(object):
    """
    An execution frame's static context.
    """

    _immutable_ = True
    _immutable_fields_ = ("lives[*]", "exs[*]", "atoms[*]", "scripts[:]",
                          "clipboards[:]")

    def __init__(self, lives, exs, atoms, scripts, clipboards):
        self.lives = lives
        self.exs = exs
        self.atoms = atoms
        self.scripts = scripts
        self.clipboards = clipboards

class MakeBytecode(MixIR.makePassTo(BytecodeIR)):
    """
    Turn non-control-flow instructions into bytecode.

    The stack layout:
     * Exprs have stack signature () -- (obj)
     * Patts have stack signature (specimen ej) -- ()
     * Calling convention:
       * Calls have stack signature (obj arg0 arg1 ... argn) -- (obj)
         * The number of arguments is captured in the atom used to call
       * Named arguments are passed as a map and use a different calling
         instruction, with signature (obj arg0 ... argn namedArgs) -- (obj)
       * Methods have stack signature (namedArgs ej args ej) -- (rv)
       * Matchers have stack signature (message ej) -- (rv)
    """

    def __init__(self):
        self.liveStacks = [[]]
        self.exStacks = [[]]
        self.atomStacks = [[]]
        self.scriptStacks = [[]]
        self.clipboardStacks = [[]]

    def pushFrame(self):
        self.liveStacks.append([])
        self.exStacks.append([])
        self.atomStacks.append([])
        self.scriptStacks.append([])
        self.clipboardStacks.append([])

    def popFrame(self):
        lives = self.liveStacks.pop()
        exs = self.exStacks.pop()
        atoms = self.atomStacks.pop()
        scripts = self.scriptStacks.pop()
        clipboards = self.clipboardStacks.pop()
        return StaticFrame(lives[:], exs[:], atoms[:], scripts[:],
                           clipboards[:])

    def addLive(self, obj):
        stack = self.liveStacks[-1]
        rv = len(stack)
        stack.append(obj)
        return rv

    def addEx(self, ex):
        stack = self.exStacks[-1]
        rv = len(stack)
        stack.append(ex)
        return rv

    def addScript(self, script):
        stack = self.scriptStacks[-1]
        rv = len(stack)
        stack.append(script)
        return rv

    def addClipboard(self, clipboard):
        stack = self.clipboardStacks[-1]
        rv = len(stack)
        stack.append(clipboard)
        return rv

    def visitLiveExpr(self, obj):
        index = self.addLive(obj)
        return BytecodeExpr([
            (LIVE, index),
        ])

    def visitExceptionExpr(self, exception):
        index = self.addEx(exception)
        return BytecodeExpr([
            (EX, index),
        ])

    def visitNullExpr(self):
        index = self.addLive(NullObject)
        return BytecodeExpr([
            (LIVE, index),
        ])

    def visitLocalExpr(self, name, idx):
        return BytecodeExpr([
            (LOCAL, idx),
        ])

    def visitFrameExpr(self, name, idx):
        return BytecodeExpr([
            (FRAME, idx),
        ])

    def visitDefExpr(self, patt, ex, rvalue):
        rv = self.visitExpr(ex)
        # (ej)
        rv = rv.addExpr(self.visitExpr(rvalue))
        # (ej specimen)
        rv = rv.add([
            (DUP, 0),
            # (ej specimen specimen)
            (NROT, 0),
            # (specimen specimen ej)
        ])
        rv = rv.addExpr(self.visitPatt(patt))
        # (specimen)
        return rv

    def makeCall(self, op, atom):
        # XXX linear-time search turns to quadratic-time performance:
        # Compiling n distinct atoms in a single frame is O(n**2).
        atomStack = self.atomStacks[-1]
        for i, a in enumerate(atomStack):
            if atom is a:
                return op, i
        atomIndex = len(atomStack)
        atomStack.append(atom)
        return op, atomIndex

    def visitCallExpr(self, obj, atom, args, namedArgs):
        rv = self.visitExpr(obj)
        for arg in args:
            rv = rv.add(self.visitExpr(arg).insts)
        if namedArgs:
            op = CALLMAP
            rv = rv.add([
                (MAKEMAP, 0),
            ])
            mapWith = [self.makeCall(CALL, WITH_2)]
            for namedArg in namedArgs:
                key = self.visitExpr(namedArg.key).insts
                value = self.visitExpr(namedArg.value).insts
                rv = rv.add(key + value + mapWith)
        else:
            op = CALL
        call = [self.makeCall(op, atom)]
        return rv.add(call)

    def makeMatchList(self, patts):
        # (xs ej)
        rv = BytecodeExpr([
            (MATCHLIST, len(patts))
        ])
        # (xn ej ... x1 ej x0 ej)
        for patt in patts:
            rv = rv.addExpr(self.visitPatt(patt))
        return rv

    def visitNamedPatt(self, namedPatt):
        # (namedArgs ej)
        rv = BytecodeExpr([
            (SWAP, 0),
            # (ej namedArgs)
            (OVER, 0),
        ])
        # (ej namedArgs ej)
        rv = rv.addExpr(self.visitExpr(namedPatt.key))
        # (ej namedArgs ej key)
        if isinstance(namedPatt.default, self.src.NullExpr):
            # No default means that we cheat: m`namedArgs.fetch(key, ej)`
            rv = rv.add([
                # (ej namedArgs ej key)
                (SWAP, 0),
                # (ej namedArgs key ej)
                # Here's the magic: No default means that we eject out
                # directly in this call.
                self.makeCall(CALL, FETCH_2),
                # (ej specimen)
            ])
        else:
            # (ej namedArgs ej key)
            rv = rv.add([
                (SWAP, 0),
                # (ej namedArgs key ej)
                (POP, 0),
                # (ej namedArgs key)
                (OVER, 0),
                # (ej namedArgs key namedArgs)
                (OVER, 0),
                # (ej namedArgs key namedArgs key)
                self.makeCall(CALL, CONTAINS_1),
                # (ej namedArgs key bool)
            ])
            # We must branch. If the key is in the map, get it; otherwise,
            # evaluate the default.
            ifExpr = self.dest.IfExpr(
                BytecodeExpr([]),
                BytecodeExpr([
                    # (ej namedArgs key)
                    self.makeCall(CALL, GET_1),
                    # (ej specimen)
                ]),
                BytecodeExpr([
                    # (ej namedArgs key)
                    (POP, 0),
                    # (ej namedArgs)
                    (POP, 0),
                    # (ej)
                ]).addExpr(self.visitExpr(namedPatt.default)),
            )
            rv = rv.addExpr(ifExpr)
        # (ej specimen)
        rv = rv.add([
            (SWAP, 0),
        ])
        # (specimen ej)
        rv = rv.addExpr(self.visitPatt(namedPatt.patt))
        # ()
        return rv

    def visitMethodExpr(self, doc, atom, patts, namedPatts, guard, body,
            localSize):
        self.pushFrame()
        # (namedArgs ej args ej)
        expr = self.makeMatchList(patts)
        # (namedArgs ej)
        for namedPatt in namedPatts:
            # (namedArgs ej)
            expr = expr.add([
                (OVER, 0),
                (OVER, 0),
            ])
            # (namedArgs ej namedArgs ej)
            expr = expr.addExpr(self.visitNamedPatt(namedPatt))
        # (namedArgs ej)
        expr = expr.add([
            (POP, 0),
            (POP, 0),
        ])
        # ()
        expr = expr.addExpr(self.visitExpr(body))
        # (rv)
        if not isinstance(guard, self.src.NullExpr):
            expr = expr.addExpr(self.addLive(NullObject))
            # (rv null)
            expr = expr.addExpr(self.visitExpr(guard))
            # (rv null guard)
            expr = expr.add([
                # (specimen ej guard)
                (NROT, 0),
                # (guard specimen ej)
                self.makeCall(CALL, COERCE_2),
                # (prize)
            ])
            # (rv)
        frame = self.popFrame()
        return self.dest.MethodExpr(doc, atom, frame, expr, localSize)

    def visitMatcherExpr(self, patt, body, localSize):
        self.pushFrame()
        # (message ej)
        rv = self.visitPatt(patt)
        # ()
        expr = rv.add(self.visitExpr(body).insts)
        # (rv)
        frame = self.popFrame()
        return self.dest.MatcherExpr(frame, expr, localSize)

    def visitClearObjectExpr(self, patt, script):
        script = self.visitScript(script)
        scriptIndex = self.addScript(script)
        rv = BytecodeExpr([
            (MAKEOBJECT, scriptIndex),
            # (obj)
            (DUP, 0),
            # (obj obj)
            (LIVE, self.addLive(NullObject)),
            # (obj obj null)
        ])
        # (obj specimen ej)
        rv = rv.addExpr(self.visitPatt(patt))
        # (obj)
        # Check whether we have a spot in the closure.
        position = script.layout.frameTable.positionOf(script.name)
        if position != -1:
            # Assign to the closure.
            rv = rv.add([
                (TIEKNOT, position),
            ])
        # (obj)
        return rv

    def visitObjectExpr(self, patt, guards, auditors, script, clipboard):
        script = self.visitScript(script)
        scriptIndex = self.addScript(script)
        # Set up guard information.
        # XXX this needs to be fixed
        guardAuditor = None
        guardInfo = GuardInfo(guards, script.layout.frameTable, script.name, guardAuditor)
        clipboard.guardInfo = guardInfo
        clipboard.auditorSize = len(auditors)
        clipboardIndex = self.addClipboard(clipboard)
        rv = BytecodeExpr([])
        for auditor in auditors:
            rv = rv.addExpr(self.visitExpr(auditor))
        rv = rv.add([
            # (auditor0 auditor1 ... auditorn)
            (AUDIT, clipboardIndex),
            # (stamps)
            (MAKESTAMPEDOBJECT, scriptIndex),
            # (obj)
            (DUP, 0),
            # (obj obj)
            (LIVE, self.addLive(NullObject)),
            # (obj obj null)
        ])
        # (obj specimen ej)
        rv = rv.addExpr(self.visitPatt(patt))
        # (obj)
        # Check whether we have a spot in the closure.
        position = script.layout.frameTable.positionOf(script.name)
        if position != -1:
            # Assign to the closure.
            rv = rv.add([
                (TIEKNOT, position),
            ])
        # (obj)
        return rv

    def makeBind(self, op, guard, idx):
        # (specimen ej)
        if isinstance(guard, self.src.NullExpr):
            rv = BytecodeExpr([
                (LIVE, self.addLive(anyGuard))
            ])
        else:
            rv = self.visitExpr(guard)
        return rv.add([
            # (specimen ej guard)
            (NROT, 0),
            # (guard specimen ej)
            # self.makeCall(CALL, COERCE_2),
            # (prize)
            (op, idx),
            # ()
        ])

    def visitBindingPatt(self, name, idx):
        return BytecodeExpr([
            # (specimen ej)
            (POP, 0),
            # (specimen)
            (BINDN, idx),
            # ()
        ])

    def visitFinalBindingPatt(self, name, guard, idx):
        return self.makeBind(BINDFB, guard, idx)

    def visitFinalSlotPatt(self, name, guard, idx):
        return self.makeBind(BINDFS, guard, idx)

    def visitIgnorePatt(self, guard):
        # (specimen ej)
        if isinstance(guard, self.src.NullExpr):
            return BytecodeExpr([
                (POP, 0),
                (POP, 0),
            ])
        else:
            guard = self.visitExpr(guard)
            return guard.add([
                # (specimen ej guard)
                (NROT, 0),
                # (guard specimen ej)
                self.makeCall(CALL, COERCE_2),
                # (prize)
                (POP, 0),
                # ()
            ])

    def visitListPatt(self, patts):
        return self.makeMatchList(patts)

    def visitNounPatt(self, name, guard, idx):
        if isinstance(guard, self.src.NullExpr):
            return BytecodeExpr([
                # (specimen ej)
                (POP, 0),
                # (specimen)
                (BINDN, idx),
                # ()
            ])
        else:
            return self.makeBind(BINDN, guard, idx)

    def visitVarBindingPatt(self, name, guard, idx):
        return self.makeBind(BINDVB, guard, idx)

    def visitVarSlotPatt(self, name, guard, idx):
        return self.makeBind(BINDVS, guard, idx)

    def visitViaPatt(self, trans, patt, _):
        # (specimen ej)
        rv = BytecodeExpr([
            (SWAP, 0),
            # (ej specimen)
            (OVER, 0),
        ])
        # (ej specimen ej)
        rv = rv.addExpr(self.visitExpr(trans))
        # (ej specimen ej trans)
        rv = rv.add([
            (NROT, 0),
            # (ej trans specimen ej)
            self.makeCall(CALL, RUN_2),
            # (ej prize)
            (SWAP, 0),
        ])
        # (prize ej)
        rv = rv.addExpr(self.visitPatt(patt))
        # ()
        return rv
