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

    return [Enum(i, label) for (i, label) in enumerate(labels)]
