from typhon.objects import Object, ConstListObject


class makeList(Object):

    def recv(self, verb, args):
        if verb == u"run":
            return ConstListObject(args)


def simpleScope():
    return {
        u"__makeList": makeList(),
    }
