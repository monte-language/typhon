"""
Finger trees, as practiced by Hinze & Paterson.

Seriously, read their paper at
http://www.staff.city.ac.uk/~ross/papers/FingerTree.pdf and then the structure
of this module will make more sense.

We don't introduce a Monoid typeclass; instead, we instantiate one ad-hoc for
every finger tree class.

This version uses erased storage to fix the recursive type problem.
"""

from rpython.rlib.rerased import new_erasing_pair

def makeFingerTreeClass(zero, add):
    """
    Produce a finger tree class.

    `zero` is the monoidal zero of the monoid for this class, and `add` is the
    monoidal binary operation.
    """

    class Node(object):
        _immutable_ = True

    class Node2(Node):

        def __init__(self, x, y, depth):
            self.x = x
            self.y = y
            self.depth = depth

        def __repr__(self):
            return "N2(%r, %r)" % (self.x, self.y)

        def asDigits(self):
            return Two(self.x, self.y, self.depth)

    class Node3(Node):

        def __init__(self, x, y, z, depth):
            self.x = x
            self.y = y
            self.z = z
            self.depth = depth

        def __repr__(self):
            return "N3(%r, %r, %r)" % (self.x, self.y, self.z)

        def asDigits(self):
            return Three(self.x, self.y, self.z, self.depth)

    eraseNode, uneraseNode = new_erasing_pair("Node")
    eraseValue, uneraseValue = new_erasing_pair("Value")

    class Digit(object):
        _immutable_ = True

    class One(Digit):
        def __init__(self, a, depth):
            self.a = a
            self.depth = depth

        def __repr__(self):
            return "1(%r)" % self.a

        def pushLeft(self, value):
            return Two(value, self.a, self.depth)

        def pushRight(self, value):
            return Two(self.a, value, self.depth)

        def popLeft(self):
            assert False, "popcorn"

        popRight = popLeft

        def asTree(self):
            return Single(self.a, self.depth)

    class Two(Digit):
        def __init__(self, a, b, depth):
            self.a = a
            self.b = b
            self.depth = depth

        def __repr__(self):
            return "2(%r, %r)" % (self.a, self.b)

        def pushLeft(self, value):
            return Three(value, self.a, self.b, self.depth)

        def pushRight(self, value):
            return Three(self.a, self.b, value, self.depth)

        def popLeft(self):
            return self.a, One(self.b, self.depth)

        def popRight(self):
            return self.b, One(self.a, self.depth)

        def asTree(self):
            return Deep(One(self.a, self.depth), Empty(self.depth + 1),
                        One(self.b, self.depth), self.depth)

    class Three(Digit):
        def __init__(self, a, b, c, depth):
            self.a = a
            self.b = b
            self.c = c
            self.depth = depth

        def __repr__(self):
            return "3(%r, %r, %r)" % (self.a, self.b, self.c)

        def pushLeft(self, value):
            return Four(value, self.a, self.b, self.c, self.depth)

        def pushRight(self, value):
            return Four(self.a, self.b, self.c, value, self.depth)

        def popLeft(self):
            return self.a, Two(self.b, self.c, self.depth)

        def popRight(self):
            return self.c, Two(self.a, self.b, self.depth)

        def asTree(self):
            # We must pick a bias here; we cannot use a Single instance to
            # keep the tree centered. I choose left, because I am left-handed.
            # ~ C.
            return Deep(Two(self.a, self.b, self.depth),
                        Empty(self.depth + 1), One(self.c, self.depth),
                        self.depth)

    class Four(Digit):
        def __init__(self, a, b, c, d, depth):
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.depth = depth

        def __repr__(self):
            return "4(%r, %r, %r, %r)" % (self.a, self.b, self.c, self.d)

        def pushLeft(self, value):
            assert False, "golfball"

        pushRight = pushLeft

        def popLeft(self):
            return self.a, Three(self.b, self.c, self.d, self.depth)

        def popRight(self):
            return self.d, Three(self.a, self.b, self.c, self.depth)

        def asTree(self):
            return Deep(Two(self.a, self.b, self.depth), Empty(self.depth + 1),
                        Two(self.c, self.d, self.depth), self.depth)

    class FingerTree(object):
        _immutable_ = True

        def pushLeft(self, value):
            return self._pushLeft(eraseValue(value))

        def pushRight(self, value):
            return self._pushRight(eraseValue(value))

        def popLeft(self):
            value, ft = self._viewLeft()
            return uneraseValue(value), ft

        def popRight(self):
            value, ft = self._viewRight()
            return uneraseValue(value), ft

    class Empty(FingerTree):

        def __init__(self, depth=0):
            self.depth = depth

        def __repr__(self):
            return "Empty"

        def _pushLeft(self, value):
            return Single(value, self.depth)

        _pushRight = _pushLeft

        def _viewLeft(self):
            return None, None

        _viewRight = _viewLeft

        def isEmpty(self):
            return True

    class Single(FingerTree):
        _immutable_ = True

        def __init__(self, value, depth):
            self.value = value
            self.depth = depth

        def __repr__(self):
            return "Single(%r)" % self.value

        def _pushLeft(self, value):
            return Deep(One(value, self.depth), Empty(self.depth + 1),
                        One(self.value, self.depth), self.depth)

        def _pushRight(self, value):
            return Deep(One(self.value, self.depth), Empty(self.depth + 1),
                        One(value, self.depth), self.depth)

        def _viewLeft(self):
            return self.value, Empty(self.depth)

        _viewRight = _viewLeft

        def isEmpty(self):
            return False

    class Deep(FingerTree):
        _immutable_ = True

        def __init__(self, left, tree, right, depth):
            assert tree.depth == depth + 1, "birch"
            assert left.depth == depth, "pine"
            assert right.depth == depth, "redwood"

            self.left = left
            self.tree = tree
            self.right = right
            self.depth = depth

        def __repr__(self):
            return "Deep%d(%r, %r, %r)" % (self.depth, self.left, self.tree,
                                           self.right)

        def _pushLeft(self, value):
            if isinstance(self.left, Four):
                node = eraseNode(Node3(self.left.b, self.left.c, self.left.d,
                                       self.depth))
                return Deep(Two(value, self.left.a, self.depth),
                            self.tree._pushLeft(node), self.right, self.depth)
            else:
                left = self.left.pushLeft(value)
                return Deep(left, self.tree, self.right, self.depth)

        def _pushRight(self, value):
            if isinstance(self.right, Four):
                node = eraseNode(Node3(self.right.a, self.right.b,
                                       self.right.c, self.depth))
                return Deep(self.left, self.tree._pushRight(node),
                            Two(self.right.d, value, self.depth), self.depth)
            else:
                right = self.right.pushRight(value)
                return Deep(self.left, self.tree, right, self.depth)

        def _viewLeft(self):
            if isinstance(self.left, One):
                value = self.left.a
                if self.tree.isEmpty():
                    return value, self.right.asTree()
                else:
                    n, tree = self.tree._viewLeft()
                    left = uneraseNode(n).asDigits()
                    return value, Deep(left, tree, self.right, self.depth)
            else:
                value, left = self.left.popLeft()
                return value, Deep(left, self.tree, self.right, self.depth)

        def _viewRight(self):
            if isinstance(self.right, One):
                value = self.right.a
                if self.tree.isEmpty():
                    return value, self.left.asTree()
                else:
                    n, tree = self.tree._viewRight()
                    right = uneraseNode(n).asDigits()
                    return value, Deep(self.left, tree, right, self.depth)
            else:
                value, right = self.right.popRight()
                return value, Deep(self.left, self.tree, right, self.depth)

        def isEmpty(self):
            return False

    return Empty

cls = makeFingerTreeClass(0, 1)
ft = cls()
for x in range(10):
    ft = ft.pushRight(x)
    print "Push", x
    print ft
while not ft.isEmpty():
    x, ft = ft.popLeft()
    print "Pop", x
    print ft
for x in range(10):
    ft = ft.pushLeft(x)
    print "Push", x
    print ft
while not ft.isEmpty():
    x, ft = ft.popRight()
    print "Pop", x
    print ft
