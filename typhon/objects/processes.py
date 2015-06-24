import os
import signal

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, StrObject, unwrapStr
from typhon.objects.root import Object, runnable


GETARGUMENTS_0 = getAtom(u"getArguments", 0)
GETPID_0 = getAtom(u"getPID", 0)
INTERRUPT_0 = getAtom(u"interrupt", 0)
RUN_2 = getAtom(u"run", 2)


@autohelp
class CurrentProcess(Object):
    """
    The current process on the local node.
    """

    def __init__(self, config):
        self.config = config

    def toString(self):
        return u"<current process (PID %d)>" % os.getpid()

    def recv(self, atom, args):
        if atom is GETARGUMENTS_0:
            return ConstList([StrObject(arg.decode("utf-8"))
                              for arg in self.config.argv])

        if atom is GETPID_0:
            return IntObject(os.getpid())

        if atom is INTERRUPT_0:
            os.kill(os.getpid(), signal.SIGINT)
            return NullObject

        raise Refused(self, atom, args)


@autohelp
class SubProcess(Object):
    """
    A subordinate process of the current process, on the local node.
    """

    def __init__(self, pid, argv):
        self.pid = pid
        self.argv = argv

    def toString(self):
        return u"<child process (PID %d)>" % self.pid

    def recv(self, atom, args):
        if atom is GETARGUMENTS_0:
            return ConstList([StrObject(arg.decode("utf-8"))
                              for arg in self.argv])

        if atom is GETPID_0:
            return IntObject(self.pid)

        if atom is INTERRUPT_0:
            os.kill(self.pid, signal.SIGINT)
            return NullObject

        raise Refused(self, atom, args)


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
        return SubProcess(pid, argv)

    # Return something.
    return NullObject
