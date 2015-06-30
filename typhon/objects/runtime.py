from rpython.rlib import rgc

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.collections import ConstMap, monteDict
from typhon.objects.data import IntObject, StrObject
from typhon.objects.root import Object


GETBUCKETS_0 = getAtom(u"getBuckets", 0)
GETHEAPSTATISTICS_0 = getAtom(u"getHeapStatistics", 0)
SIZE_0 = getAtom(u"size", 0)


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


class Heap(Object):
    """
    A statistical snapshot of the heap.
    """

    size = 0

    def __init__(self):
        self.buckets = {}

    def accountObject(self, obj):
        name = obj.__class__.__name__
        if name not in self.buckets:
            self.buckets[name] = 0
        self.buckets[name] += 1
        self.size += 1

    def recv(self, atom, args):
        if atom is GETBUCKETS_0:
            d = monteDict()
            for name, size in self.buckets.items():
                d[StrObject(name)] = IntObject(size)
            return ConstMap(d)

        if atom is SIZE_0:
            return IntObject(self.size)

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

        raise Refused(self, atom, args)
