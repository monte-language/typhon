class Rope(object):
    """
    A binary tree of fragments of some stringlike collection.
    """

    def add(self, other):
        return Branch(self, other)

    def slice(self, start, stop):
        assert start >= 0, "Failed to prove non-negative start"
        assert stop < self.size, "Stop was too large"
        piece, _ = self.splitAt(stop)
        _, rv = piece.splitAt(start)
        return rv


class Leaf(Rope):

    _immutable_ = True

    def __init__(self, fragment):
        self.fragment = fragment
        self.size = len(fragment)

    def __repr__(self):
        return "Leaf(%d, %r)" % (self.size, self.fragment)

    def get(self, index):
        assert index >= 0, "Failed to prove non-negative index"
        assert index < self.size, "Implementation error in rope"
        return self.fragment[index]

    def splitAt(self, index):
        assert index >= 0, "Failed to prove non-negative index"
        assert index < self.size, "Implementation error in rope"
        return Leaf(self.fragment[:index]), Leaf(self.fragment[index:])


class Branch(Rope):

    _immutable_ = True

    def __init__(self, left, right):
        self.left = left
        self.right = right
        self.size = left.size + right.size

    def __repr__(self):
        return "Branch(%d, %r, %r)" % (self.size, self.left, self.right)

    def get(self, index):
        assert index >= 0, "Failed to prove non-negative index"
        assert index < self.size, "Implementation error in rope"
        if index < self.left.size:
            return self.left.get(index)
        else:
            return self.right.get(index - self.left.size)

    def splitAt(self, index):
        assert index >= 0, "Failed to prove non-negative index"
        assert index < self.size, "Implementation error in rope"
        if index < self.left.size:
            left, rightPiece = self.left.splitAt(index)
            return left, Branch(rightPiece, self.right)
        elif index > self.left.size:
            leftPiece, right = self.right.splitAt(index - self.left.size)
            return Branch(self.left, leftPiece), right
        else:
            return self.left, self.right


def makeRope(fragment):
    # XXX might need to specialize?
    return Leaf(fragment)
