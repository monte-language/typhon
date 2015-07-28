from rpython.rlib import rgc

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.objects.collections import ConstList, monteDict
from typhon.objects.data import IntObject, StrObject
from typhon.objects.root import Object, method
from typhon.objects.user import ScriptObject
from typhon.specs import Any, Int, Map


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
            self.sizes[name] = 0
        self.buckets[name] += 1
        sizeOf = obj.sizeOf()
        self.sizes[name] += sizeOf
        self.objectCount += 1
        self.memoryUsage += sizeOf

    @method([], Map)
    def getBuckets(self):
        assert isinstance(self, Heap)
        d = monteDict()
        for name, count in self.buckets.items():
            size = self.sizes.get(name, -1)
            d[StrObject(name)] = ConstList([IntObject(size),
                                            IntObject(count)])

    @method([], Int)
    def getMemoryUsage(self):
        assert isinstance(self, Heap)
        return self.memoryUsage

    @method([], Int)
    def getObjectCount(self):
        assert isinstance(self, Heap)
        return self.objectCount


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

    @method([], Int)
    def getAlarms(self):
        assert isinstance(self, ReactorStats)
        return len(self.reactor.alarmQueue.heap)

    @method([], Int)
    def getSelectables(self):
        assert isinstance(self, ReactorStats)
        return len(self.reactor._selectables)


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

    @method([], Any)
    def getHeapStatistics(self):
        return makeHeapStats()

    @method([], Any)
    def getReactorStatistics(self):
        return makeReactorStats()
