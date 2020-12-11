from rpython.rlib import rgc
from rpython.rlib.rerased import new_erasing_pair

# from typhon import ruv
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
        if isinstance(obj, InterpObject):
            name = obj.getDisplayName()
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

    @method("Map")
    def getBuckets(self):
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
    for obj in getMonteObjects():
        heap.accountObject(obj)
    return heap


@autohelp
class LoopHandle(Object):
    """
    A handle.
    """

    def __init__(self, handle):
        self.handle = handle

def walkCB(handle, erased):
    l = uneraseList(erased)
    l.append(handle)

eraseList, uneraseList = new_erasing_pair("handleList")

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
        l = []
        # ruv.walk(self.loop, walkCB, eraseList(l))
        return [LoopHandle(h) for h in l]


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
    """

    __immutable__ = True

    def __init__(self, sections):
        self.sections = sections

    @method("Map")
    def getSections(self):
        "A map from section names to the relative amount of time spent."
        rv = monteMap()
        for k, v in self.sections.items():
            rv[wrapBytes(k)] = DoubleObject(v)
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
