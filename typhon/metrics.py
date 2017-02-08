from __future__ import division

from time import time

from rpython.rlib.debug import debug_print


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


class Recorder(object):

    startTime = endTime = 0

    def __init__(self):
        self.timings = {}
        self.rates = {}
        self.contextStack = []

    def start(self):
        self.startTime = time()

    def stop(self):
        self.endTime = time()

    def addTiming(self, label, elapsed):
        if label not in self.timings:
            self.timings[label] = 0
        self.timings[label] += elapsed

    def startSegment(self):
        self.currentSegment = time()

    def finishSegment(self):
        elapsed = time() - self.currentSegment
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

    def printResults(self):
        total = self.endTime - self.startTime
        debug_print("Total recorded time:", total)
        debug_print("Recorded times:")
        for label in self.timings:
            t = self.timings[label]
            debug_print("~", label + ":", t, "(%s)" % percent(t, total))

        debug_print("Recorded rates:")
        for label, rate in self.rates.iteritems():
            debug_print("~", label + ":", rate.rate())

    def context(self, label):
        return RecorderContext(self, label)


_recorder = Recorder()
def globalRecorder():
    return _recorder
