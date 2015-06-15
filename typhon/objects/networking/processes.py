import os

from typhon.atoms import getAtom
from typhon.objects.collections import unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, unwrapStr
from typhon.objects.root import runnable

RUN_2 = getAtom(u"run", 2)

@runnable(RUN_2)
def makeProcess(args):
    # XXX first draft: Just do it.
    # Next time around, I'll make this into a Callback. And then eventually a
    # Selectable, probably...
    executable = unwrapStr(args[0]).encode("utf-8")
    argv = [unwrapStr(arg).encode("utf-8") for arg in unwrapList(args[1])]

    pid = os.fork()
    if pid == 0:
        # Child.
        os.execv(executable, argv)
    else:
        # Parent.
        return IntObject(pid)

    # Return something.
    return NullObject
