"""
RPython-compatible singleton enum objects.
"""

def makeEnum(group, labels):
    class Enum(object):
        """
        An enumeration.
        """

        _immutable_ = True

        def __init__(self, i, label):
            self.asInt = i
            self.repr = u"<%s(%s)>" % (group, label)

        def __repr__(self):
            return self.repr.encode("utf-8")

    return [Enum(i, label) for (i, label) in enumerate(labels)]
