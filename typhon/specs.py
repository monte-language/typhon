"""
Type specifications.
"""


class Spec(object):
    """
    A type specification.
    """


class AnySpec(Spec):

    def wrap(_, specimen):
        return specimen

    def unwrap(_, specimen):
        return specimen

Any = AnySpec()

# Data specifications.

class BoolSpec(Spec):

    def wrap(_, specimen):
        from typhon.objects.constants import wrapBool
        return wrapBool(specimen)

    def unwrap(_, specimen):
        from typhon.objects.constants import unwrapBool
        return unwrapBool(specimen)

Bool = BoolSpec()


class CharSpec(Spec):

    def wrap(_, specimen):
        from typhon.objects.data import CharObject
        return CharObject(specimen)

    def unwrap(_, specimen):
        from typhon.objects.data import unwrapChar
        return unwrapChar(specimen)

Char = CharSpec()


class IntSpec(Spec):

    def wrap(_, specimen):
        from typhon.objects.data import IntObject
        return IntObject(specimen)

    def unwrap(_, specimen):
        from typhon.objects.data import unwrapInt
        return unwrapInt(specimen)

Int = IntSpec()


class StrSpec(Spec):

    def wrap(_, specimen):
        from typhon.objects.data import StrObject
        return StrObject(specimen)

    def unwrap(_, specimen):
        from typhon.objects.data import unwrapStr
        return unwrapStr(specimen)

Str = StrSpec()


class VoidSpec(Spec):

    def wrap(_, specimen):
        from typhon.objects.constants import NullObject
        return NullObject

    def unwrap(_, specimen):
        from typhon.objects.constants import NullObject
        if specimen is not NullObject:
            from typhon.errors import WrongType
            raise WrongType(u"Object was not null!")
        return None

Void = VoidSpec()

# Collection specifications.

class ListSpec(Spec):

    def wrap(_, specimen):
        from typhon.objects.collections import ConstList
        return ConstList(specimen)

    def unwrap(_, specimen):
        from typhon.objects.collections import unwrapList
        return unwrapList(specimen)

List = ListSpec()
