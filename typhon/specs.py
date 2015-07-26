"""
Type specifications.
"""


class Spec(object):
    pass


class AnySpec(Spec):

    def wrap(_, specimen):
        return specimen

    def unwrap(_, specimen):
        return specimen

Any = AnySpec()


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
