from typhon.atoms import getAtom
from typhon.errors import userError
from typhon.vats import currentVat
from typhon.objects.collections.lists import wrapList
from typhon.objects.collections.maps import EMPTY_MAP
from typhon.objects.data import NullObject, StrObject, unwrapBool
from typhon.objects.equality import EQUAL, TraversalKey, optSame, isSameEver
from typhon.objects.guards import anyGuard
from typhon.objects.refs import (EVENTUAL, NEAR, Promise, UnconnectedRef,
                                 isResolved, resolution)
from typhon.objects.root import audited
from typhon.objects.slots import FinalSlot

HANDLESEND_3 = getAtom(u"handleSend", 3)
HANDLESENDONLY_3 = getAtom(u"handleSendOnly", 3)
RUN_3 = getAtom(u"run", 3)


def send(ref, atom, args, namedArgs):
    if isinstance(ref, Promise):
        return ref.sendAll(atom, args, namedArgs)
    else:
        vat = currentVat.get()
        return vat.send(ref, atom, args, namedArgs)


def sendOnly(ref, atom, args, namedArgs):
    if isinstance(ref, Promise):
        ref.sendAllOnly(atom, args, namedArgs)
    else:
        vat = currentVat.get()
        vat.sendOnly(ref, atom, args, namedArgs)


class Proxy(Promise):
    def __init__(self, handler, resolutionBox):
        if not handler.isSettled():
            raise userError(u"Proxy handler not settled: " +
                            handler.toString())
        self.handler = handler
        self.resolutionBox = resolutionBox
        self.committed = False

    def commit(self):
        if self.committed:
            raise userError(u"already commited")
        self.committed = True
        if isinstance(self.resolutionBox, FinalSlot):
            res = self.resolutionBox.get()
        else:
            res = UnconnectedRef(StrObject(
                u"Resolution promise of a proxy handled by " +
                self.handler.toString() +
                u" didn't resolve to a FinalSlot, but " +
                self.resolutionBox.toString() +
                u" instead."))
            self.resolutionBox = FinalSlot(res, anyGuard)
        self.handler = None
        return res

    def checkSlot(self):
        if self.committed:
            return True
        self.resolutionBox = resolution(self.resolutionBox)
        if isResolved(self.resolutionBox):
            self.commit()
            return True
        return False

    def eq(self, other):
        if not isinstance(other, Proxy):
            return False
        if self.checkSlot() or other.checkSlot():
            raise userError(u"equals comparison of resolved proxy is"
                            u" impossible")
        return optSame(self.handler, other.handler) is EQUAL

    def state(self):
        if self.checkSlot():
            o = self.resolutionBox.get()
            if isinstance(o, Promise):
                return o.state()
            else:
                return NEAR
        else:
            return EVENTUAL

    def optProblem(self):
        if self.checkSlot():
            ref = self.resolutionBox.get()
            if isinstance(ref, Promise):
                return ref.optProblem()
        return NullObject

    def resolutionRef(self):
        if self.checkSlot():
            ref = self.resolutionBox.get()
            if isinstance(ref, Promise):
                return ref.resolutionRef()
            return ref
        return self

    def callAll(self, atom, args, namedArgs):
        if self.checkSlot():
            return self.resolutionBox.get().recvNamed(atom, args, namedArgs)
        else:
            raise userError(u"not synchronously callable (%s)" %
                            atom.repr.decode("utf-8"))

    def sendAll(self, atom, args, namedArgs):
        if self.checkSlot():
            ref = self.resolutionBox.get()
            return send(ref, atom, args, namedArgs)
        else:
            return send(self.handler, HANDLESEND_3, [StrObject(atom.verb),
                                                     wrapList(args),
                                                     namedArgs], EMPTY_MAP)

    def sendAllOnly(self, atom, args, namedArgs):
        if self.checkSlot():
            ref = self.resolutionBox.get()
            sendOnly(ref, atom, args, namedArgs)
        else:
            sendOnly(self.handler, HANDLESENDONLY_3, [StrObject(atom.verb),
                                                      wrapList(args),
                                                      namedArgs], EMPTY_MAP)
        return NullObject

    def toString(self):
        if self.checkSlot():
            return self.resolutionBox.get().toString()
        else:
            return self._proxyToString()


@audited.Selfless
class DisconnectedRef(UnconnectedRef):
    """
    A DisconnectedRef is a broken ref that used to point to an object in a
    different vat but doesn't anymore.
    """

    def __init__(self, handler, resolutionIdentity, problem):
        UnconnectedRef.__init__(self, problem)
        self.handler = handler
        self.resolutionIdentity = resolutionIdentity

    def computeHash(self, depth):
        return self.handler.computeHash(depth)

    def eq(self, other):
        if not isinstance(other, DisconnectedRef):
            return False
        result = (isSameEver(self.handler, other.handler) and
                  isSameEver(self.resolutionIdentity,
                             other.resolutionIdentity))
        if (result and not isSameEver(self._problem, other._problem)):
            raise userError(u"Ref invariant violation: disconnected refs with "
                            u" same identity but different problems")
        return result


@audited.Selfless
class FarRef(Proxy):
    """
    A FarRef is a settled reference to an object in another vat. It may become
    a DisconnectedRef if the other vat is no longer accessible.

    Synchronous calls are rejected, and sends are delivered to the ref's
    handler object.
    """

    def __init__(self, handler, resolutionBox):
        Proxy.__init__(self, handler, resolutionBox)
        self.resolutionIdentity = TraversalKey(resolutionBox)

    def computeHash(self, depth):
        return self.handler.computeHash(depth)

    def eq(self, other):
        if not isinstance(other, FarRef):
            return False
        return (Proxy.eq(self, other) and
                optSame(self.resolutionIdentity,
                        other.resolutionIdentity) is EQUAL)

    def isResolved(self):
        return True

    def resolutionRef(self):
        if self.checkSlot():
            return self.resolutionBox.get()
        return self

    def commit(self):
        # A FarRef can only stop proxying if it becomes disconnected, when it
        # resolves to a DisconnectedRef.
        handler = self.handler
        resolution = Proxy.commit(self)
        if not isinstance(resolution, UnconnectedRef):
            problem = StrObject(
                u"Attempt to resolve a far ref handled by " +
                handler.toString() +
                u"to a different identity (" +
                resolution.toString() + u")")
        else:
            problem = resolution._problem
        resolution = DisconnectedRef(handler, self.resolutionIdentity,
                                     problem)
        self.resolutionBox = FinalSlot(resolution, anyGuard)
        self.resolutionIdentity = None

    def _proxyToString(self):
        return u"<Far ref>"


class RemotePromise(Proxy):
    """
    A RemotePromise is an unresolved reference received from another vat. It
    may resolve to a FarRef, a near object, or become broken.

    Until it is resolved, synchronous calls are prohibited and message sends
    are delivered to the ref's message handler. After resolution calls and
    sends are both forwarded to the resolution object.
    """
    def eq(self, other):
        if not isinstance(other, RemotePromise):
            return False
        return (Proxy.eq(self, other) and
                optSame(self.resolutionBox,
                        other.resolutionBox) is EQUAL)

    def _proxyToString(self):
        return u"<Promise>"

    def isResolved(self):
        if self.checkSlot():
            return isResolved(self.resolutionBox.get())
        return False


def makeProxy(handler, resolutionBox, resolved):
    if not handler.isSettled():
        raise userError(u"Proxy handler not settled")
    if unwrapBool(resolved):
        return FarRef(handler, resolutionBox)
    else:
        return RemotePromise(handler, resolutionBox)
