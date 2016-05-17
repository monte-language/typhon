"""
Machinery for "zero-cost" table-driven exception handling.
"""

from typhon.smallcaps import ops

class ExceptionTable(object):
    """
    A data structure for storing exception-handling locations.
    """

    def __init__(self):
        self.ejectors = []
        self.stack = []
        self.log = []

    def beginEjector(self, start):
        rv = len(self.ejectors)
        self.ejectors.append(start)
        self.stack.append((ops.ET_ESCAPE, start))
        return rv

    def endEjector(self, end):
        op, start = self.stack.pop()
        assert op is ops.ET_ESCAPE
        for index, s in enumerate(self.ejectors):
            if start == s:
                self.log.append((ops.ET_ESCAPE, start, index, end))
                break
        else:
            assert False

    def beginFinally(self, start):
        self.stack.append((ops.ET_FINALLY, start))

    def endFinally(self, end):
        op, start = self.stack.pop()
        assert op is ops.ET_FINALLY
        self.log.append((ops.ET_FINALLY, start, 0, end))

    def beginTry(self, start):
        self.stack.append((ops.ET_TRY, start))

    def endTry(self, end):
        op, start = self.stack.pop()
        assert op is ops.ET_TRY
        self.log.append((ops.ET_TRY, start, 0, end))

    def shouldBranchAt(self, pc):
        "Whether a branch is indicated by the log."
        for op, start, _, end in self.log:
            if start == pc:
                return end
        return -1

    def removeInst(self, pc):
        log = []
        for op, start, index, end in self.log:
            if start > pc:
                start -= 1
            if end > pc:
                end -= 1
            if end > start:
                log.append((op, start, index, end))
        self.log = log

    def finalize(self):
        if self.log:
            size = self.log[-1][3]
            arr = [(None, 0, 0)] * size
            # Painter's algorithm.
            for op, start, index, end in reversed(self.log):
                row = op, index, end
                for x in range(start, end):
                    arr[x] = row
            # Trim from the front.
            offset = 0
            while arr[offset][0] is None:
                offset += 1
            arr = arr[offset:]
            return offset, arr
        else:
            return 0, []

    def ejectorSize(self):
        return len(self.ejectors)
