import os
import signal

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.collections.lists import ConstList, unwrapList
from typhon.objects.collections.maps import ConstMap, monteMap, unwrapMap
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, IntObject, StrObject, unwrapBytes
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat


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
            # XXX monteMap()
            d = monteMap()
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
            return ConstList([BytesObject(arg) for arg in self.argv])

        if atom is GETENVIRONMENT_0:
            # XXX monteMap()
            d = monteMap()
            for key, value in self.env.items():
                k = BytesObject(key)
                v = BytesObject(value)
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

    # Third incarnation: libuv-powered and requiring bytes.
    executable = unwrapBytes(args[0])
    # This could be an LC, but doing it this way fixes the RPython annotation
    # for the list to be non-None.
    argv = []
    for arg in unwrapList(args[1]):
        s = unwrapBytes(arg)
        assert s is not None, "proven impossible by hand"
        argv.append(s)
    env = {}
    for (k, v) in unwrapMap(args[2]).items():
        env[unwrapBytes(k)] = unwrapBytes(v)
    packedEnv = [k + '=' + v for (k, v) in env.items()]

    vat = currentVat.get()
    try:
        pid = ruv.spawn(vat.uv_loop, file=executable, args=argv, env=packedEnv)
        return SubProcess(pid, argv, env)
    except ruv.UVError as uve:
        raise userError(u"makeProcess: Couldn't spawn process: %s" %
                        uve.repr().decode("utf-8"))
