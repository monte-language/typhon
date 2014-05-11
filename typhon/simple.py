from typhon.objects import (Object, ConstListObject, EqualizerObject,
                            FalseObject, NullObject, TrueObject)


class makeList(Object):

    def recv(self, verb, args):
        if verb == u"run":
            return ConstListObject(args)


def simpleScope():
    return {
        u"__equalizer": EqualizerObject(),
        u"__makeList": makeList(),
        u"false": FalseObject,
        u"null": NullObject,
        u"true": TrueObject,
    }
