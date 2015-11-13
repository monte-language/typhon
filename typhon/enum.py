"""
RPython-compatible singleton enum objects.
"""

def makeEnum(group, labels):
    class Enum(object):
        """
        An enumeration.
        """

        _immutable_ = True

        def __init__(self, label):
            self.repr = u"<%s(%s)>" % (group, label)

    return [Enum(label) for label in labels]
