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

def makeFingerTreeClass(zero, add, measure):
    """
    Produce a finger tree class.

    `zero` is the monoidal zero of the monoid for this class, and `add` is the
    monoidal binary operation; `measure` is a function which turns values into
    monoidal values.
    """

    class Node(object):
        _immutable_ = True

    class Node2(Node):

        def __init__(self, x, y, depth):
            self.x = x
            self.y = y
            self.depth = depth

            if depth:
                x = uneraseNode(x)
                y = uneraseNode(y)
                self.measure = add(x.measure, y.measure)
            else:
                x = uneraseValue(x)
                y = uneraseValue(y)
                self.measure = add(measure(x), measure(y))

        def __repr__(self):
            return "N2(measure=%d, %r, %r)" % (self.measure, self.x, self.y)

        def asDigits(self):
            return Two(self.x, self.y, self.depth)

    class Node3(Node):

        def __init__(self, x, y, z, depth):
            self.x = x
            self.y = y
            self.z = z
            self.depth = depth

            if depth:
                x = uneraseNode(x)
                y = uneraseNode(y)
                z = uneraseNode(z)
                self.measure = add(add(x.measure, y.measure), z.measure)
            else:
                x = uneraseValue(x)
                y = uneraseValue(y)
                z = uneraseValue(z)
                self.measure = add(add(measure(x), measure(y)), measure(z))

        def __repr__(self):
            return "N3(measure=%d, %r, %r, %r)" % (self.measure, self.x,
                    self.y, self.z)

        def asDigits(self):
            return Three(self.x, self.y, self.z, self.depth)

    eraseNode, uneraseNode = new_erasing_pair("Node")
    eraseValue, uneraseValue = new_erasing_pair("Value")

    def gatherNodes(l, depth):
        nodes = []
        while l:
            if len(l) == 2:
                node = eraseNode(Node2(l[0], l[1], depth))
                nodes.append(node)
                l = l[2:]
            elif len(l) == 4:
                node = eraseNode(Node2(l[0], l[1], depth))
                nodes.append(node)
                node = eraseNode(Node2(l[2], l[3], depth))
                nodes.append(node)
                l = l[4:]
            else:
                node = eraseNode(Node3(l[0], l[1], l[2], depth))
                nodes.append(node)
                l = l[3:]
        return nodes

    class Digit(object):
        _immutable_ = True

        def split(self, predicate, i):
            right = self.asList()
            left = []
            while right:
                if len(right) == 1:
                    return left, right[0], []
                item = right.pop(0)
                if self.depth:
                    m = uneraseNode(item).measure
                else:
                    m = measure(uneraseValue(item))
                i = add(i, m)
                if predicate(i):
                    return left, item, right
                else:
                    left.append(item)
            assert False, "spumoni"

    class One(Digit):
        def __init__(self, a, depth):
            self.a = a
            self.depth = depth

            if depth:
                a = uneraseNode(a)
                self.measure = a.measure
            else:
                a = uneraseValue(a)
                self.measure = measure(a)

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

        def asList(self):
            return [self.a]

    class Two(Digit):
        def __init__(self, a, b, depth):
            self.a = a
            self.b = b
            self.depth = depth

            if depth:
                a = uneraseNode(a)
                b = uneraseNode(b)
                self.measure = add(a.measure, b.measure)
            else:
                a = uneraseValue(a)
                b = uneraseValue(b)
                self.measure = add(measure(a), measure(b))

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

        def asList(self):
            return [self.a, self.b]

    class Three(Digit):
        def __init__(self, a, b, c, depth):
            self.a = a
            self.b = b
            self.c = c
            self.depth = depth

            if depth:
                a = uneraseNode(a)
                b = uneraseNode(b)
                c = uneraseNode(c)
                self.measure = add(add(a.measure, b.measure), c.measure)
            else:
                a = uneraseValue(a)
                b = uneraseValue(b)
                c = uneraseValue(c)
                self.measure = add(add(measure(a), measure(b)), measure(c))

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

        def asList(self):
            return [self.a, self.b, self.c]

    class Four(Digit):
        def __init__(self, a, b, c, d, depth):
            self.a = a
            self.b = b
            self.c = c
            self.d = d
            self.depth = depth

            if depth:
                a = uneraseNode(a)
                b = uneraseNode(b)
                c = uneraseNode(c)
                d = uneraseNode(d)
                self.measure = add(add(a.measure, b.measure),
                                   add(c.measure, d.measure))
            else:
                a = uneraseValue(a)
                b = uneraseValue(b)
                c = uneraseValue(c)
                d = uneraseValue(d)
                self.measure = add(add(measure(a), measure(b)),
                                   add(measure(c), measure(d)))

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

        def asList(self):
            return [self.a, self.b, self.c, self.d]

    def listToDigit(l, depth):
        size = len(l)
        if size == 1:
            return One(l[0], depth)
        elif size == 2:
            return Two(l[0], l[1], depth)
        elif size == 3:
            return Three(l[0], l[1], l[2], depth)
        else:
            assert size == 4, "divot"
            return Four(l[0], l[1], l[2], l[3], depth)

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

        def add(self, other):
            return self._concat([], other)

        def split(self, predicate):
            if isinstance(self, Empty):
                return self, self
            elif predicate(self.measure):
                left, item, right = self._split(predicate, zero)
                return left, right._pushLeft(item)
            else:
                return self, Empty(self.depth)

        def asList(self):
            l = []
            while not self.isEmpty():
                value, self = self._viewLeft()
                l.append(uneraseValue(value))
            return l

    class Empty(FingerTree):

        measure = zero

        def __init__(self, depth=0):
            self.depth = depth

        def __repr__(self):
            return "Empty"

        def _pushLeft(self, value):
            return Single(value, self.depth)

        _pushRight = _pushLeft

        def _viewLeft(self):
            raise ValueError("rosewood")

        _viewRight = _viewLeft

        def isEmpty(self):
            return True

        def _concat(self, middle, other):
            for item in middle:
                other = other._pushLeft(item)
            return other

        def _split(self, predicate, i):
            raise ValueError("egghead")

    class Single(FingerTree):
        _immutable_ = True

        def __init__(self, value, depth):
            self.value = value
            self.depth = depth

            if depth:
                self.measure = uneraseNode(value).measure
            else:
                self.measure = measure(uneraseValue(value))

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

        def _concat(self, middle, other):
            for item in middle:
                other = other._pushLeft(item)
            return other._pushLeft(self.value)

        def _split(self, predicate, i):
            return Empty(self.depth), self.value, Empty(self.depth)

    class Deep(FingerTree):
        _immutable_ = True

        def __init__(self, left, tree, right, depth):
            assert tree.depth == depth + 1, "birch"
            assert left.depth == depth, "pine"
            assert right.depth == depth, "redwood"

            assert isinstance(left, Digit), "sinister"
            assert isinstance(right, Digit), "dexter"

            self.left = left
            self.tree = tree
            self.right = right
            self.depth = depth

            self.measure = add(add(left.measure, tree.measure), right.measure)

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

        def _concat(self, middle, other):
            if isinstance(other, Empty):
                for item in middle:
                    self = self._pushRight(item)
                return self
            elif isinstance(other, Single):
                for item in middle:
                    self = self._pushRight(item)
                return self._pushRight(other.value)
            elif isinstance(other, Deep):
                newLeft = self.left
                newRight = self.right
                l = gatherNodes(self.right.asList() + other.left.asList(),
                                self.depth)
                newTree = self.tree._concat(l, other.tree)
                return Deep(newLeft, newTree, newRight, self.depth)
            else:
                assert False, "willow"

        def _split(self, predicate, i):
            j = add(i, self.left.measure)
            if predicate(j):
                left, item, right = self.left.split(predicate, i)
                if left:
                    leftSplit = listToDigit(left, self.depth).asTree()
                else:
                    leftSplit = Empty(self.depth)
                if right:
                    rightSplit = Deep(listToDigit(right, self.depth),
                                      self.tree, self.right, self.depth)
                elif self.tree.isEmpty():
                    rightSplit = self.right.asTree()
                else:
                    value, tree = self.tree._viewLeft()
                    rightSplit = Deep(uneraseNode(value).asDigits(), tree,
                                      self.right, self.depth)
                return leftSplit, item, rightSplit
            k = add(j, self.tree.measure)
            if predicate(k):
                leftTree, itemTree, rightTree = self.tree._split(predicate, j)
                digits = uneraseNode(itemTree).asDigits()
                leftList, item, rightList = digits.split(predicate,
                        add(j, leftTree.measure))
                if leftList:
                    leftSplit = Deep(self.left, leftTree,
                                     listToDigit(leftList, self.depth),
                                     self.depth)
                elif leftTree.isEmpty():
                    leftSplit = self.left.asTree()
                else:
                    value, leftTree = leftTree._viewRight()
                    leftSplit = Deep(self.left, leftTree,
                                     uneraseNode(value).asDigits(),
                                     self.depth)
                if rightList:
                    rightSplit = Deep(listToDigit(rightList, self.depth),
                                      rightTree, self.right, self.depth)
                elif rightTree.isEmpty():
                    rightSplit = self.right.asTree()
                else:
                    value, rightTree = rightTree._viewLeft()
                    rightSplit = Deep(uneraseNode(value).asDigits(),
                                      rightTree, self.right, self.depth)
                return leftSplit, item, rightSplit
            else:
                left, item, right = self.right.split(predicate, k)
                if left:
                    leftSplit = Deep(self.left, self.tree,
                                     listToDigit(left, self.depth),
                                     self.depth)
                elif self.tree.isEmpty():
                    leftSplit = self.left.asTree()
                else:
                    value, tree = self.tree._viewRight()
                    leftSplit = Deep(self.left, tree,
                                     uneraseNode(value).asDigits(),
                                     self.depth)
                if right:
                    rightSplit = listToDigit(right, self.depth).asTree()
                else:
                    rightSplit = Empty(self.depth)
                return leftSplit, item, rightSplit

    return Empty

# import random
# cls = makeFingerTreeClass(0, lambda x, y: x + y, lambda _: 1)
# ft = cls()
# for x in range(100):
#     ft = ft.pushRight(x)
#     print "+",
#     if random.random() > 0.80:
#         _, ft = ft.popLeft()
#         print "-",
#     if random.random() > 0.95:
#         ft = ft.add(ft)
#         print "*",
# print
# while not ft.isEmpty():
#     x, ft = ft.popLeft()
#     print "-",
# print
# for x in range(100):
#     ft = ft.pushLeft(x)
#     print "+",
#     if random.random() > 0.80:
#         _, ft = ft.popRight()
#         print "-",
#     if random.random() > 0.95:
#         ft = ft.add(ft)
#         print "*",
# print
# while not ft.isEmpty():
#     x, ft = ft.popRight()
#     print "-",
# print
# 
# for x in range(100):
#     ft = ft.pushLeft(x)
#     print "+",
# for x in range(100):
#     left, right = ft.split(lambda i: i > x)
#     print "/",
# while not ft.isEmpty():
#     x, ft = ft.popRight()
#     print "-",
# print
