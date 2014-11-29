from time import time


def percent(part, whole):
    f = 100 * part / whole
    return "(%f%%)" % f


class RecorderContext(object):

    startTime = 0

    def __init__(self, recorder, label):
        self.recorder = recorder
        self.label = label

    def __enter__(self):
        self.startTime = time()

    def __exit__(self, *unused):
        after = time()
        elapsed = after - self.startTime
        self.recorder.addTiming(self.label, elapsed)


class Recorder(object):

    startTime = endTime = 0

    def __init__(self):
        self.timings = {}

    def start(self):
        self.startTime = time()

    def stop(self):
        self.endTime = time()

    def addTiming(self, label, elapsed):
        if label not in self.timings:
            self.timings[label] = 0
        self.timings[label] += elapsed

    def record(self, label, action):
        before = time()
        rv = action()
        after = time()

        self.addTiming(label, after - before)

        return rv

    def printResults(self):
        total = self.endTime - self.startTime
        print "Total recorded time:", total
        print "Recorded times:"
        for label in self.timings:
            t = self.timings[label]
            print "~", label, ":", t, percent(t, total)

    def context(self, label):
        return RecorderContext(self, label)
