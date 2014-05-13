from typhon.errors import Ejecting, Refused
from typhon.objects import (Object, ConstListObject, EjectorObject,
                            EqualizerObject, FalseObject, NullObject,
                            TrueObject)


class accumulateList(Object):

    def recv(self, verb, args):
        if verb == u"run" and len(args) == 2:
            rv = []

            iterable = args[0]
            mapper = args[1]
            iterator = iterable.recv(u"_makeIterator", [])
            ej = EjectorObject()

            while True:
                try:
                    values = iterator.recv(u"next", [ej])
                    if not isinstance(values, ConstListObject):
                        raise RuntimeError
                    rv.append(mapper.recv(u"run", values._l))
                except Ejecting as e:
                    if e.ejector == ej:
                        break

            ej.deactivate()

            return ConstListObject(rv)
        raise Refused(verb, args)


class makeList(Object):

    def recv(self, verb, args):
        if verb == u"run":
            return ConstListObject(args)
        raise Refused(verb, args)


def simpleScope():
    return {
        u"__accumulateList": accumulateList(),
        u"__equalizer": EqualizerObject(),
        u"__makeList": makeList(),
        u"false": FalseObject,
        u"null": NullObject,
        u"true": TrueObject,
    }
