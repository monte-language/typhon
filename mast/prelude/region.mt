# Module sugar cannot be used here since we are replacing names we received from preludeScope.
def region(loader):
    def DeepFrozenStamp :DeepFrozen := loader."import"("boot")["DeepFrozenStamp"]
    def TransparentStamp :DeepFrozen := loader."import"("boot")["TransparentStamp"]

    def cmpInf(left, right) as DeepFrozen:
        "Compare, but treat `null` as -∞ on the left and ∞ on the right."

        # -∞ is smaller than anything else.
        if (left == null):
            return -1

        # ∞ is larger than anything else.
        if (right == null):
            return 1

        # Business as usual.
        return left.op__cmp(right)


    # Convention: Null means -infinity on the LHS and +infinity on the RHS.
    def _makeTopSet(guard :DeepFrozen, left :NullOk[guard], leftClosed :Bool,
                    right :NullOk[guard], rightClosed :Bool) as DeepFrozenStamp:

        # Invariant: The LHS is less than or equal to the RHS. It's fine for them
        # to be equal, although in that case, both the LHS and RHS must be closed.
        # (Otherwise, there'd be an indeterminate number of members in the set. A
        # closed set with LHS <=> RHS has one member.)
        if (left != null && right != null):
            if (left > right):
                throw(`Invariant failed: $left > $right`)
            else if (left <=> right &! (leftClosed & rightClosed)):
                throw(`Invariant failed: $left <=> $right but not closed`)

        return object topSet as DeepFrozenStamp:
            "A set in the topological sense, with a left-hand and right-hand
             endpoint."

            to _printOn(out):
                out.print(leftClosed.pick("[", "("))
                out.print((left == null).pick("-∞", M.toQuote(left)))
                out.print(", ")
                out.print((right == null).pick("∞", M.toQuote(right)))
                out.print(rightClosed.pick("]", ")"))

            to _uncall():
                return [_makeTopSet, "run", [guard, left, leftClosed, right,
                                             rightClosed], [].asMap()]

            # We will be calling .next() in this iterator. If .next() doesn't
            # work, then we allow the exception to raise. This might be annoying
            # for Str and Double, but I don't want to special-case them and cause
            # people to be surprised when user-defined interfaces also fail. ~ C.
            to _makeIterator():
                var i :Int := 0
                var position :guard := left

                if (!leftClosed):
                    position := position.next()

                return object topSetIterator:
                    "An iterator for a topset."

                    to _makeIterator():
                        return topSetIterator

                    to next(ej):
                        def cmp := cmpInf(position, right)
                        if (cmp.aboveZero() || (cmp.isZero() & !rightClosed)):
                            throw.eject(ej, "Iteration stopped: topset exhausted")

                        def rv := [i, position]
                        i += 1
                        position := position.next()

                        return rv

            to asTuple():
                "Easily-unpacked value for pattern-matching."
                return [left, leftClosed, right, rightClosed]

            to contains(value :guard) :Bool:
                "Whether a value is in this topset."

                # Start on the left.
                if (left != null):
                    if (value < left):
                        return false
                    else if (value <=> left &! leftClosed):
                        return false

                # And now the right.
                if (right != null):
                    if (value > right):
                        return false
                    else if (value <=> right &! rightClosed):
                        return false

                # It doesn't lie outside the set; therefore, it's within the set.
                return true

            to isFull() :Bool:
                "Whether this topset contains all values of its type."
                return left == null & right == null

            to intersects(other) :Bool:
                "Whether this topset and another topset have any overlap."
                def [otherLeft, otherLC, otherRight, otherRC] := other.asTuple()
                def leftFits := ((left == null | otherRight == null) ||
                                 left < otherRight ||
                                 (left <=> otherRight && (otherRC & leftClosed)))
                def rightFits := ((right == null | otherLeft == null) ||
                                  right > otherLeft ||
                                  (right <=> otherLeft &&
                                   (otherLC & rightClosed)))
                return leftFits & rightFits

    # This no longer really resembles MarkM's original regions. Instead of the
    # edgelist, these regions use a closed-open endpoint representation, with a
    # simpler composition.
    def _makeOrderedRegion(guard :DeepFrozen, myName :Str,
                           topSets :List[DeepFrozen]) as DeepFrozen:
        "Make regions for sets of objects with total ordering."

        def region(newTopSets) as DeepFrozenStamp:
            return _makeOrderedRegion(guard, myName, newTopSets)

        def size :Int := topSets.size()

        def myTypeR :Same[guard] := guard # for SubrangeGuard audit

        # XXX needs "implements Guard", when that makes sense
        object self implements DeepFrozenStamp, SubrangeGuard[guard], SubrangeGuard[DeepFrozen]:
            "An ordered region."

            # mostly prints in Monte sugared expression syntax
            to _printOn(out):
                if (size == 0):
                    out.print("<empty ")
                else:
                    out.print("<")
                    # Cannot fail since size is non-zero.
                    def [head] + tail := topSets
                    out.print(head)
                    for topSet in (tail):
                        out.print(" | ")
                        out.print(topSet)
                out.print(` $myName region>`)

            to _uncall():
                return [_makeOrderedRegion, "run", [guard, myName, topSets],
                        [].asMap()]

            to getTopSets():
                "The topsets of this region."
                return topSets

            to contains(pos :guard) :Bool:
                "Whether a given position is in this region."

                # XXX linear search. This can, and should, be binary search, *but*
                # we must prove that our list of topsets is sorted.
                for topSet in (topSets):
                    if (topSet.contains(pos)):
                        return true
                return false

            to run(pos) :Bool:
                "Whether a given position is in this region.

                 Alias of `contains/1`."
                return self.contains(pos)

            to coerce(var specimen, ej) :myTypeR:
                "This guard is unretractable."

                specimen := guard.coerce(specimen, ej)
                if (self(specimen)):
                    return specimen
                else:
                    throw.eject(ej, `${M.toQuote(specimen)} is not in $self`)

            to isEmpty() :Bool:
                "Whether there are any positions in this region."
                return size == 0

            to isFull() :Bool:
                "Whether this region contains all possible positions."
                return size == 1 && topSets[0].isFull()

            to add(offset):
                "Translate this region by an offset."
                return region([for topSet in (topSets) topSet + offset])

            to subtract(offset):
                "Translate this region by an offset."
                return region([for topSet in (topSets) topSet - offset])

            to not():
                "The region containing precisely those positions not in this
                 region."

                if (size == 0):
                    # We are the empty region; return the full region.
                    return region([_makeTopSet(guard, null, false, null, false)])

                # We move from left to right for obvious reasons.
                # XXX this requires that we are sorted!
                def rv := [].diverge()
                def [head] + tail := topSets
                def [left, leftClosed, var right, var rightClosed] := head.asTuple()
                if (left != null):
                    # We don't include -∞, so our complement must.
                    rv.push(_makeTopSet(guard, null, false, left, !leftClosed))
                for topSet in (tail):
                    def [nextLeft, nextLC, nextRight, nextRC] := topSet.asTuple()
                    rv.push(_makeTopSet(guard, right, !rightClosed, nextLeft,
                                        !nextLC))
                    right := nextRight
                    rightClosed := nextRC
                if (right != null):
                    # We don't include ∞, so our complement must.
                    rv.push(_makeTopSet(guard, right, !rightClosed, null, false))

                return region(rv.snapshot())

            to and(other):
                "The intersection of this region with another region."

                # If we are empty, then we can't possibly intersect the other
                # region. If they are full, then we are already our own
                # intersection.
                if (size == 0 || other.isFull()):
                    return self

                # Ditto for them.
                if (self.isFull() || other.isEmpty()):
                    return other

                def otherTopSets := other.getTopSets()
                def otherSize := otherTopSets.size()

                # Invariant: Neither list of topsets is empty, proved above.
                # Invariant: Neither region is full, proved above.

                def rv := [].diverge()
                var ourIter := topSets._makeIterator()
                var otherIter := otherTopSets._makeIterator()
                # Won't fail this time.
                var ourNext := ourIter.next(null)[1]
                var otherNext := otherIter.next(null)[1]

                while (true):
                    def [ourLeft, ourLC, ourRight, ourRC] := ourNext.asTuple()
                    def [otherLeft, otherLC, otherRight, otherRC] := otherNext.asTuple()
                    if (ourNext.intersects(otherNext)):
                        # Hit! Perform the intersection and trim the top. We
                        # already know that our left edge is the leading edge,
                        # so we're going to go with their left edge. We'll
                        # select whichever right edge is next.

                        # Whether our left edge is before their left edge.
                        def weAreFirst := (ourLeft == null ||
                                           (otherLeft != null &&
                                            (ourLeft < otherLeft ||
                                            (ourLeft <=> otherLeft &&
                                             (ourLC | !otherLC)))))
                        # And whether our right edge is after their right edge.
                        def weAreLast := (ourRight == null ||
                                          (otherRight != null &&
                                           (ourRight > otherRight ||
                                           (ourRight <=> otherRight &&
                                            (!ourRC | otherRC)))))

                        # We should be set. Based on the judgments we just made,
                        # we'll make the intersecting topset and push it onto the
                        # list. We'll also rebuild the right-hand leftovers from
                        # the intersection for the next iteration.
                        def [newLeft, newLC] := if (weAreFirst) {
                            [otherLeft, otherLC]
                        } else {
                            [ourLeft, ourLC]
                        }
                        def [newRight, newRC] := if (weAreLast) {
                            [otherRight, otherRC]
                        } else {
                            [ourRight, ourRC]
                        }
                        rv.push(_makeTopSet(guard, newLeft, newLC, newRight,
                                            newRC))
                        # Reassemble the remainder. We're using right-hand edges
                        # as left-hand edges here, so we need a null check. If a
                        # new LHS would be null, but it was on the RHS, then it
                        # used to be +∞, and we cannot forge another edge there,
                        # so we'll break instead.
                        if (weAreLast):
                            if (otherRight == null):
                                break
                            ourNext := _makeTopSet(guard, otherRight, !otherRC,
                                                   ourRight, ourRC)
                        else:
                            if (ourRight == null):
                                break
                            otherNext := _makeTopSet(guard, ourRight, !ourRC,
                                                     otherRight, otherRC)
                    else:
                        # No intersection. Drop the earlier topset and continue.
                        def weAreFirst := (ourLeft == null ||
                                           (otherLeft != null &&
                                            (ourLeft < otherLeft ||
                                            (ourLeft <=> otherLeft &&
                                             (ourLC | !otherLC)))))
                        if (weAreFirst):
                            ourNext := ourIter.next(__break)[1]
                        else:
                            otherNext := otherIter.next(__break)[1]
                return region(rv.snapshot())

            to or(other):
                "The union of this region with another region."
                return !(!self & !other)

            to butNot(other):
                "The union of this region with the complement of another region."
                return self & !other

            to _makeIterator():
                "Finite iteration over discrete positions in the region."

                if (size == 0):
                    return []._makeIterator()
                else if (size == 1):
                    return topSets[0]._makeIterator()

                # Our locals. The strategy is to iterate over each iterator from
                # each topset in order.
                var i :Int := 0
                var topSetIndex :Int := 0
                var currentIterator := topSets[0]._makeIterator()

                return object regionIterator:
                    "Iterator for a region."

                    to next(ej):
                        escape ejTopSet:
                            def rv := [i, currentIterator.next(ejTopSet)[1]]
                            i += 1
                            return rv
                        catch _:
                            topSetIndex += 1
                            if (topSetIndex >= size):
                                throw.eject(ej, "Iteration finished")
                            currentIterator := topSets[topSetIndex]._makeIterator()
                            return regionIterator.next(ej)

            # NB: I have omitted .descending/0 but it is not hard to implement.
            # You will want to add it to topsets first and then to regions. ~ C.

            to op__cmp(other) :Double:
                "Whether the other region is a proper subset of this region."

                def selfExtra := !(self & !other).isEmpty()
                def otherExtra := !(other & !self).isEmpty()
                if (selfExtra):
                    if (otherExtra):
                        # Both have left-overs, so they're incomparable.
                        return NaN
                    else:
                        # Only self has left-overs, so we're a strict
                        # superset of other
                        return 1.0
                else:
                    if (otherExtra):
                        # Only other has left-overs, so we're a strict
                        # subset of other
                        return -1.0
                    else:
                        # No left-overs, so we're as-big-as each other
                        return 0.0
        return self
    def _makeOrderedSpace
    object _selmipriMakeOrderedSpace as DeepFrozenStamp:
        "The maker of ordered vector spaces.

         This object implements several Monte operators, including those which
         provide ordered space syntax."

        # Given a type whose reflexive (x <=> x) instances are fully
        # ordered, this makes an OrderedSpace for making Regions and
        # Twisters for those instances using operator notation.
        to run(myType :DeepFrozen, myName :Str):

            def region(newTopSets) as DeepFrozenStamp:
                return _makeOrderedRegion(myType, myName, newTopSets)

            object maybeSubrangeDeepFrozen:
                to audit(audition):
                    if (DeepFrozen.supersetOf(myType)):
                        audition.ask(SubrangeGuard[DeepFrozen])
                    return false

            # Be prepared to show our authorization at the border
            def myTypeR :Same[myType] := myType

            # The OrderedSpace delegates to the myType.
            return object OrderedSpace extends myType as DeepFrozenStamp implements maybeSubrangeDeepFrozen, Selfless, TransparentStamp:
                "An ordered vector space.

                 As a guard, this object admits any value in the set of objects in
                 the space. Comparison operators may be used on this object to
                 create subguards which only admit a partition of the set."

                # Just uses the name used to construct this OrderedSpace
                to _printOn(out):
                    out.print(myName)

                to _uncall():
                    return [_makeOrderedSpace, "run", [myType, myName], [].asMap()]

                to coerce(specimen, ej) :myTypeR:
                    return myType.coerce(specimen, ej)

                to op__cmp(myY :myType):
                    "Return regions representing the possible positions for
                     comparisons."

                    return object regionMaker:
                        # (myType < myY)
                        to belowZero():
                            return region([_makeTopSet(myType, null, false, myY,
                                                       false)])

                        # (myType <= myY)
                        to atMostZero():
                            return region([_makeTopSet(myType, null, false, myY,
                                                       true)])

                        # (myType <=> myY)
                        to isZero():
                            return region([_makeTopSet(myType, myY, true, myY,
                                                       true)])

                        # (myType >= myY)
                        to atLeastZero():
                            return region([_makeTopSet(myType, myY, true, null,
                                                       false)])

                        # (myType > myY)
                        to aboveZero():
                            return region([_makeTopSet(myType, myY, false, null,
                                                       false)])

                to add(myOffset):
                    "Add an offset to all positions in this space."

                    return object twister:
                        to _printOn(out):
                            out.print(`($myName + $myOffset)`)

                        to run(addend :myType):
                            return addend + myOffset

                        to getOffset():
                            return myOffset

                        to add(moreOffset):
                            return OrderedSpace + (myOffset + moreOffset)

                        to subtract(moreOffset):
                            return twister + -moreOffset

                to subtract(offset):
                    "Subtract an offset from all positions in this space."
                    return OrderedSpace + -offset

                to makeRegion(left :myType, leftClosed :Bool, right :myType,
                              rightClosed :Bool):
                    "Make a region from a pair of endpoints."
                    return region([_makeTopSet(myType, left, leftClosed, right,
                                               rightClosed)])

                to makeEmptyRegion():
                    "Make the empty region."
                    return region([])


    # The space cache. Hopefully this is not often-touched.
    def spaces := [].asMap().diverge()


    object bind _makeOrderedSpace extends _selmipriMakeOrderedSpace as DeepFrozenStamp:
        "The maker of ordered vector spaces.

         This object implements several Monte operators, including those which
         provide ordered space syntax."

        to spaceOfGuard(guard):
            "Return the ordered space corresponding to a given guard."

            return spaces.fetch(guard, fn {
                def space := _makeOrderedSpace(guard, M.toQuote(guard))
                spaces[guard] := space
                # Fixpoint, just in case.
                spaces[space] := space
                space
            })

        to spaceOfValue(value):
            "Return the ordered space corresponding to a given value.

             The correspondence is obtained via Miranda
             _getAllegedInterface(), so values should be sure to override that
             Miranda method."

            def guard := value._getAllegedInterface()
            return _makeOrderedSpace.spaceOfGuard(guard)

        to op__till(start, bound):
            "The operator `start`..!`bound`.

             This is equivalent to (space ≥ `start`) ∪ (space < `bound`) for the
             ordered space containing `start` and `bound`."

            def space := _makeOrderedSpace.spaceOfValue(start)
            # If the start is not strictly less than the bound, then we take
            # the m`LHS..!RHS` syntax to mean that the RHS should *definitely*
            # be excluded, even if that means that there's next to nothing
            # left on the LHS. Assume that some member M of the space
            # satisfies m`LHS <= M && M < RHS`; but, if m`LHS >= RHS`, then at
            # least one of those conditions is false. Therefore, M doesn't
            # exist and the region is empty.
            # Discussion: https://github.com/monte-language/typhon/issues/121
            # ~ C.
            return if (start >= bound):
                space.makeEmptyRegion()
            else:
                # Closed on bottom but not on top.
                space.makeRegion(start, true, bound, false)

        to op__thru(start, bound):
            "The operator `start`..`bound`.

             This is equivalent to (space ≥ `start`) ∪ (space ≤ `bound`) for the
             ordered space containing `start` and `bound`."

            def space := _makeOrderedSpace.spaceOfValue(start)
            # By a similar logic as with op__till. ~ C.
            return if (start > bound):
                space.makeEmptyRegion()
            else:
                # Closed on both ends.
                return space.makeRegion(start, true, bound, true)


    return [
        "Bytes" => _makeOrderedSpace.spaceOfGuard(Bytes),
        "Char" => _makeOrderedSpace.spaceOfGuard(Char),
        "Double" => _makeOrderedSpace.spaceOfGuard(Double),
        "Int" => _makeOrderedSpace.spaceOfGuard(Int),
        "Str" => _makeOrderedSpace.spaceOfGuard(Str),
        => _makeTopSet,
        => _makeOrderedRegion,
        => _makeOrderedSpace,
    ]
