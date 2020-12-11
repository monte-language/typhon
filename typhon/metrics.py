from __future__ import division

from time import clock

from rpython.rlib.debug import debug_print
from rpython.rlib.listsort import make_timsort_class


def percent(part, whole):
    f = 100 * part / whole
    return "%f%%" % f


class RecorderRate(object):

    total = 0
    success = 0

    def yes(self):
        self.total += 1
        self.success += 1

    def no(self):
        self.total += 1

    def observe(self, b):
        self.total += 1
        if b:
            self.success += 1
        return b

    def rate(self):
        return percent(self.success, self.total)


class RecorderContext(object):

    startTime = 0

    def __init__(self, recorder, label):
        self.recorder = recorder
        self.label = label

    def __enter__(self):
        self.recorder.pushContext(self.label)

    def __exit__(self, *unused):
        self.recorder.popContext()


def scriptCountCmp(left, right):
    return left[1] > right[1]

ScriptSorter = make_timsort_class(lt=scriptCountCmp)


class Recorder(object):

    startTime = endTime = 0

    def __init__(self):
        self.timings = {}
        self.rates = {}
        self.scripts = {}
        self.contextStack = []

    def start(self):
        self.startTime = clock()

    def stop(self):
        self.endTime = clock()

    def addTiming(self, label, elapsed):
        if label not in self.timings:
            self.timings[label] = 0
        self.timings[label] += elapsed

    def startSegment(self):
        self.currentSegment = clock()

    def finishSegment(self):
        elapsed = clock() - self.currentSegment
        self.addTiming(self.contextStack[-1], elapsed)

    def pushContext(self, label):
        if self.contextStack:
            self.finishSegment()
        self.contextStack.append(label)
        self.startSegment()

    def popContext(self):
        self.finishSegment()
        self.contextStack.pop()
        if self.contextStack:
            self.startSegment()

    def getRateFor(self, label):
        if label not in self.rates:
            self.rates[label] = RecorderRate()
        return self.rates[label]

    def makeInstanceOf(self, label):
        if label in self.scripts:
            self.scripts[label] += 1
        else:
            self.scripts[label] = 1

    def topScripts(self):
        items = self.scripts.items()
        ScriptSorter(items).sort()
        return items[:10]

    def getTimings(self):
        total = clock() - self.startTime
        rv = {}
        unaccounted = 1.0
        for label, timing in self.timings.items():
            section = timing / total
            unaccounted -= section
            rv[label] = section
        rv[u"unaccounted"] = unaccounted
        return rv

    def printResults(self):
        total = self.endTime - self.startTime
        debug_print("Total recorded time:", total)
        debug_print("Recorded times:")
        for label in self.timings:
            t = self.timings[label]
            debug_print("~", label.encode("utf-8") + ":", t, "(%s)" % percent(t, total))

        debug_print("Recorded rates:")
        for label, rate in self.rates.iteritems():
            debug_print("~", label + ":", rate.rate())

        debug_print("Most commonly-instantiated scripts:")
        for label, count in self.topScripts():
            debug_print("~", label.encode("utf-8") + ":", count)

    def context(self, label):
        return RecorderContext(self, label)


_recorder = Recorder()
def globalRecorder():
    return _recorder
