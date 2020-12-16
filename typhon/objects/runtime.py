from rpython.rlib import rgc
from rpython.rtyper.lltypesystem import rffi

from typhon import ruv
from typhon.autohelp import autohelp, method
from typhon.nano.interp import InterpObject
from typhon.objects.collections.lists import wrapList
from typhon.objects.collections.maps import monteMap
from typhon.objects.data import DoubleObject, IntObject, StrObject, unwrapBytes, wrapBytes
from typhon.objects.root import Object


# The fun of GC management. This is all very subject to change and only works
# with rpython 0.1.4 from PyPI. Sorry. ~ C.

def clear_gcflag_extra(fromlist):
    pending = fromlist[:]
    while pending:
        gcref = pending.pop()
        if rgc.get_gcflag_extra(gcref):
            rgc.toggle_gcflag_extra(gcref)
            pending.extend(rgc.get_rpy_referents(gcref))

def getHeapObjects():
    """
    Iterate through the heap.

    We return two lists. The first is a list of Monte objects. The second is a
    list of (name, size) pairs.

    The division lets us ask Monte objects for their name and size using
    .getDisplayName() and .sizeOf(); we can't do that during GC iteration.
    """
    roots = [gcref for gcref in rgc.get_rpy_roots() if gcref]
    pending = roots[:]
    objs = []
    lls = []
    while pending:
        gcref = pending.pop()
        if not rgc.get_gcflag_extra(gcref):
            rgc.toggle_gcflag_extra(gcref)
            w_obj = rgc.try_cast_gcref_to_instance(Object, gcref)
            if w_obj is not None:
                objs.append(w_obj)
            else:
                clsIndex = rgc.get_rpy_type_index(gcref)
                name = u"~%d" % clsIndex
                size = rgc.get_rpy_memory_usage(gcref)
                lls.append((name, size))
            pending.extend(rgc.get_rpy_referents(gcref))
    clear_gcflag_extra(roots)
    rgc.assert_no_more_gcflags()
    return objs, lls


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

    def accountObject(self, name, size):
        if name not in self.buckets:
            self.buckets[name] = 0
            self.sizes[name] = 0
        self.buckets[name] += 1
        self.sizes[name] += size
        self.objectCount += 1
        self.memoryUsage += size

    def accountMonteObject(self, obj):
        if isinstance(obj, InterpObject):
            name = obj.getDisplayName()
        else:
            name = obj.__class__.__name__.decode("utf-8")
        self.accountObject(name, obj.sizeOf())

    @method("Map")
    def getBuckets(self):
        """
        Memory usage by object type.

        Bucket names starting with ~ reflect internal interpreter structures.
        """
        d = monteMap()
        for name, count in self.buckets.items():
            size = self.sizes.get(name, -1)
            d[StrObject(name)] = wrapList([IntObject(size), IntObject(count)])
        return d

    @method("Int")
    def getMemoryUsage(self):
        return self.memoryUsage

    @method("Int")
    def getObjectCount(self):
        return self.objectCount


def makeHeapStats():
    """
    Compute some information about the heap.
    """

    heap = Heap()
    objs, lls = getHeapObjects()
    for obj in objs:
        heap.accountMonteObject(obj)
    for name, size in lls:
        heap.accountObject(name, size)
    return heap


# Prebuild a container for loop handles, so that we can use it for
# preallocated storage.
class LoopWalker(object):
    def __init__(self):
        self.handles = []
loopWalker = LoopWalker()

# Callback for ruv.walk().
def walkCB(handle, _):
    loopWalker.handles.append(handle)

@autohelp
class LoopHandle(Object):
    """
    A low-level reactor handle.
    """

    def __init__(self, handle):
        self.handle = handle

    @method("Bool")
    def isActive(self):
        """
        Whether the reactor is actively considering this handle.
        """
        return ruv.isActive(self.handle)

    @method("Bool")
    def isClosing(self):
        """
        Whether the reactor is trying to finalize this handle.
        """
        return ruv.isClosing(self.handle)

@autohelp
class LoopStats(Object):
    """
    Information about the event loop.

    This object is unsafe because it refers directly to the (read-only) vital
    statistics of the runtime's reactor.
    """

    def __init__(self, loop):
        self.loop = loop

    @method("List")
    def getHandles(self):
        handles = loopWalker.handles = []
        ruv.walk(self.loop, walkCB, None)
        loopWalker.handles = []
        return [LoopHandle(h) for h in handles]


def makeReactorStats():
    """
    Compute some information about the reactor.
    """

    # XXX what a hack
    from typhon.vats import currentVat
    loop = currentVat.get().uv_loop
    return LoopStats(loop)


@autohelp
class TimerStats(Object):
    """
    How Typhon has been using its time.

    When Typhon exits certain critical sections, it measures the cumulative
    elapsed time spent in those sections. This includes time spent taking vat
    turns and waiting for I/O.

    Specifically, Typhon has timings for the following sections:

    * "mast": Loading and deserializing code from disk
    * "nanopass": Optimizing loaded code
    * "deepfrozen": Auditing objects with DeepFrozen
    * "prelude": Executing code before vats are ready
    * "vatturn": Vats taking turns
    * "io": Performing platform I/O
    * "unaccounted": Everything else not in its own section
    """

    __immutable__ = True

    def __init__(self, sections):
        self.sections = sections

    @method("Map")
    def getSections(self):
        "A map from section names to the relative amount of time spent."
        rv = monteMap()
        for k, v in self.sections.items():
            rv[StrObject(k)] = DoubleObject(v)
        return rv


def makeTimerStats():
    from typhon.metrics import globalRecorder
    recorder = globalRecorder()
    sections = recorder.getTimings()
    return TimerStats(sections)


@autohelp
class ConfigConfig(Object):
    """
    Allow changing some settings of the runtime.
    """

    def __init__(self, config):
        self._config = config

    @method("List")
    def getLoggingTags(self):
        "The current logging tags."
        return [wrapBytes(bs) for bs in self._config.loggerTags]

    @method("Void", "List")
    def setLoggingTags(self, tags):
        "Change the logging tags."
        self._config.loggerTags = [unwrapBytes(bs) for bs in tags]
        self._config.enableLogging()


@autohelp
class CurrentRuntime(Object):
    """
    The Typhon runtime.

    This object is a platform-specific view into the configuration and
    performance of the current runtime in the current process.

    This object is necessarily unsafe and nondeterministic.
    """

    def __init__(self, config):
        self._config = config

    @method("Any")
    def getCrypt(self):
        "Get platform-specific cryptographic tools."
        from typhon.objects.crypt import Crypt
        return Crypt()

    @method("Any")
    def getHeapStatistics(self):
        """
        Take a snapshot of the heap.

        The snapshot is taken unsafely and immediately, but does not permit
        dereferencing. Only the types and sizes of objects are recorded.
        """
        return makeHeapStats()

    @method("Any")
    def getReactorStatistics(self):
        "Take a snapshot of the reactor."
        return makeReactorStats()

    @method("Any")
    def getTimerStatistics(self):
        "Take a snapshot of how time has been spent."
        return makeTimerStats()

    @method("Any")
    def getConfiguration(self):
        "Access Typhon's internal configuration."
        return ConfigConfig(self._config)
