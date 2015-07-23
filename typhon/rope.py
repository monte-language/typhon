class Rope(object):
    """
    A binary tree of fragments of some stringlike collection.
    """

    _immutable_ = True

    def add(self, other):
        return Branch(self, other)

    def slice(self, start, stop):
        assert start >= 0, "Failed to prove non-negative start"
        if stop < self.size:
            piece, _ = self.splitAt(stop)
        else:
            piece = self
        _, rv = piece.splitAt(start)
        return rv

    def put(self, index, value):
        assert index >= 0, "Failed to prove non-negative index"
        assert index < self.size, "Index was too large"
        if index == 0:
            return Leaf([value]).add(self.slice(1, self.size))
        else:
            left = self.slice(0, index)
            right = self.slice(index + 1, self.size)
            return left.add(Leaf([value])).add(right)

    def multiply(self, count):
        # XXX this can be sped up using poor man's counting
        rv = self
        for _ in range(count - 1):
            rv = rv.add(self)
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

    def iterate(self):
        return self.fragment


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

    def iterate(self):
        return self.left.iterate() + self.right.iterate()
        # stack = [self.right, self.left]
        # while stack:
        #     rope = stack.pop()
        #     if isinstance(rope, Leaf):
        #         for item in rope.fragment:
        #             yield item
        #     elif isinstance(rope, Branch):
        #         stack.append(rope.right)
        #         stack.append(rope.left)
        #     else:
        #         assert False, "Impossible case"


def makeRope(fragment):
    # XXX might need to specialize?
    return Leaf(fragment)
