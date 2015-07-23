from rpython.rlib import rgc

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.collections import ConstList, ConstMap, monteDict
from typhon.objects.data import IntObject, StrObject
from typhon.objects.root import Object
from typhon.objects.user import ScriptObject


GETALARMS_0 = getAtom(u"getAlarms", 0)
GETBUCKETS_0 = getAtom(u"getBuckets", 0)
GETHEAPSTATISTICS_0 = getAtom(u"getHeapStatistics", 0)
GETMEMORYUSAGE_0 = getAtom(u"getMemoryUsage", 0)
GETOBJECTCOUNT_0 = getAtom(u"getObjectCount", 0)
GETREACTORSTATISTICS_0 = getAtom(u"getReactorStatistics", 0)
GETSELECTABLES_0 = getAtom(u"getSelectables", 0)


# The fun of GC management. This is all very subject to change and only works
# with rpython 0.1.4 from PyPI. Sorry. ~ C.

def clear_gcflag_extra(fromlist):
    pending = fromlist[:]
    while pending:
        gcref = pending.pop()
        if rgc.get_gcflag_extra(gcref):
            rgc.toggle_gcflag_extra(gcref)
            pending.extend(rgc.get_rpy_referents(gcref))

def getMonteObjects():
    roots = [gcref for gcref in rgc.get_rpy_roots() if gcref]
    pending = roots[:]
    result_w = []
    while pending:
        gcref = pending.pop()
        if not rgc.get_gcflag_extra(gcref):
            rgc.toggle_gcflag_extra(gcref)
            w_obj = rgc.try_cast_gcref_to_instance(Object, gcref)
            if w_obj is not None:
                result_w.append(w_obj)
            pending.extend(rgc.get_rpy_referents(gcref))
    clear_gcflag_extra(roots)
    rgc.assert_no_more_gcflags()
    return result_w


@autohelp
class Heap(Object):
    """
    A statistical snapshot of the heap.
    """

    objectCount = 0
    memoryUsage = 0

    def __init__(self):
        self.buckets = {}
        self.sizes = {}

    def accountObject(self, obj):
        if isinstance(obj, ScriptObject):
            name = obj.displayName
        else:
            name = obj.__class__.__name__.decode("utf-8")
        if name not in self.buckets:
            self.buckets[name] = 0
            self.sizes[name] = rgc.get_rpy_memory_usage(obj)
        self.buckets[name] += 1
        self.objectCount += 1
        self.memoryUsage += self.sizes[name]

    def recv(self, atom, args):
        if atom is GETBUCKETS_0:
            d = monteDict()
            for name, count in self.buckets.items():
                size = self.sizes.get(name, -1)
                d[StrObject(name)] = ConstList.fromList([IntObject(size),
                                                IntObject(count)])
            return ConstMap(d)

        if atom is GETMEMORYUSAGE_0:
            return IntObject(self.memoryUsage)

        if atom is GETOBJECTCOUNT_0:
            return IntObject(self.objectCount)

        raise Refused(self, atom, args)


def makeHeapStats():
    """
    Compute some information about the heap.
    """

    heap = Heap()
    for obj in getMonteObjects():
        heap.accountObject(obj)
    return heap


@autohelp
class ReactorStats(Object):
    """
    Information about the reactor.

    This object is unsafe because it refers directly to the (read-only) vital
    statistics of the runtime's reactor.
    """

    def __init__(self, reactor):
        self.reactor = reactor

    def recv(self, atom, args):
        if atom is GETALARMS_0:
            return IntObject(len(self.reactor.alarmQueue.heap))

        if atom is GETSELECTABLES_0:
            return IntObject(len(self.reactor._selectables))

        raise Refused(self, atom, args)


def makeReactorStats():
    """
    Compute some information about the reactor.
    """

    # XXX what a hack
    from typhon.vats import currentVat
    reactor = currentVat.get()._reactor
    return ReactorStats(reactor)


@autohelp
class CurrentRuntime(Object):
    """
    The Typhon runtime.

    This object is a platform-specific view into the configuration and
    performance of the current runtime in the current process.

    This object is necessarily unsafe and nondeterministic.
    """

    def recv(self, atom, args):
        if atom is GETHEAPSTATISTICS_0:
            return makeHeapStats()

        if atom is GETREACTORSTATISTICS_0:
            return makeReactorStats()

        raise Refused(self, atom, args)
