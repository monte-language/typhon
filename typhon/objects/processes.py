import os
import signal

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.collections import (ConstList, ConstMap, monteDict,
                                        unwrapList, unwrapMap)
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, StrObject, unwrapStr
from typhon.objects.root import Object, runnable


GETARGUMENTS_0 = getAtom(u"getArguments", 0)
GETENVIRONMENT_0 = getAtom(u"getEnvironment", 0)
GETPID_0 = getAtom(u"getPID", 0)
INTERRUPT_0 = getAtom(u"interrupt", 0)
RUN_3 = getAtom(u"run", 3)


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

        if atom is GETENVIRONMENT_0:
            d = monteDict()
            for key, value in os.environ.items():
                k = StrObject(key.decode("utf-8"))
                v = StrObject(value.decode("utf-8"))
                d[k] = v
            return ConstMap(d)

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

    def __init__(self, pid, argv, env):
        self.pid = pid
        self.argv = argv
        self.env = env

    def toString(self):
        return u"<child process (PID %d)>" % self.pid

    def recv(self, atom, args):
        if atom is GETARGUMENTS_0:
            return ConstList([StrObject(arg.decode("utf-8"))
                              for arg in self.argv])

        if atom is GETENVIRONMENT_0:
            d = monteDict()
            for key, value in self.env.items():
                k = StrObject(key.decode("utf-8"))
                v = StrObject(value.decode("utf-8"))
                d[k] = v
            return ConstMap(d)

        if atom is GETPID_0:
            return IntObject(self.pid)

        if atom is INTERRUPT_0:
            os.kill(self.pid, signal.SIGINT)
            return NullObject

        raise Refused(self, atom, args)


@runnable(RUN_3)
def makeProcess(args):
    """
    Create a subordinate process on the current node from the given
    executable, arguments, and environment.
    """

    # XXX second draft: Done, but ugh.
    # Next time around, I'll make this into a Callback. And then eventually a
    # Selectable, probably...
    executable = unwrapStr(args[0]).encode("utf-8")
    argv = [unwrapStr(arg).encode("utf-8") for arg in unwrapList(args[1])]
    env = {}
    for k, v in unwrapMap(args[2]).items():
        env[unwrapStr(k).encode("utf-8")] = unwrapStr(v).encode("utf-8")

    pid = os.fork()
    if pid < 0:
        # fork() errored.
        raise userError(u"Couldn't spawn subprocess")
    elif pid == 0:
        # Child.
        os.execve(executable, argv, env)
    else:
        # Parent.
        return SubProcess(pid, argv, env)

    # Convince RPython that all exits out of this function return an object.
    return NullObject
