import os
import signal

from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.lltype import nullptr

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.collections.lists import ConstList, unwrapList
from typhon.objects.collections.maps import (EMPTY_MAP, ConstMap, monteMap,
                                             unwrapMap)
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, IntObject, StrObject, unwrapBytes
from typhon.objects.networking.streams import StreamDrain, StreamFount
from typhon.objects.root import Object, audited
from typhon.objects.refs import makePromise
from typhon.vats import currentVat, scopedVat


FLOWTO_1 = getAtom(u"flowTo", 1)
GETARGUMENTS_0 = getAtom(u"getArguments", 0)
GETENVIRONMENT_0 = getAtom(u"getEnvironment", 0)
GETPID_0 = getAtom(u"getPID", 0)
INTERRUPT_0 = getAtom(u"interrupt", 0)
RUN_3 = getAtom(u"run", 3)
WAIT_0 = getAtom(u"wait", 0)

EXITSTATUS_0 = getAtom(u"exitStatus", 0)
TERMINATIONSIGNAL_0 = getAtom(u"terminationSignal", 0)


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
class ProcessExitInformation(Object):
    """
    Holds a process' exitStatus and terminationSignal
    """

    def __init__(self, exitStatus, terminationSignal):
        self.exitStatus = exitStatus
        self.terminationSignal = terminationSignal

    def toString(self):
        return (u'<ProcessExitInformation exitStatus=%d,'
                u' terminationSignal=%d>' % (self.exitStatus,
                                             self.terminationSignal))

    def recv(self, atom, args):
        if atom is EXITSTATUS_0:
            return IntObject(self.exitStatus)

        if atom is TERMINATIONSIGNAL_0:
            return IntObject(self.terminationSignal)

        raise Refused(self, atom, args)


@autohelp
class SubProcess(Object):
    """
    A subordinate process of the current process, on the local node.
    """
    EMPTY_PID = -1
    EMPTY_EXIT_AND_SIGNAL = (-1, -1)

    def __init__(self, vat, process, argv, env):
        self.pid = self.EMPTY_PID
        self.process = process
        self.argv = argv
        self.env = env
        self.exit_and_signal = self.EMPTY_EXIT_AND_SIGNAL
        self.resolvers = []
        self.vat = vat
        ruv.stashProcess(process, (self.vat, self))

    def retrievePID(self):
        if self.pid == self.EMPTY_PID:
            self.pid = intmask(self.process.c_pid)

    def exited(self, exit_status, term_signal):
        if self.pid == self.EMPTY_PID:
            self.retrievePID()
        self.exit_and_signal = (intmask(exit_status), intmask(term_signal))
        toResolve, self.resolvers = self.resolvers, []

        with scopedVat(self.vat):
            for resolver in toResolve:
                self.resolveWaiter(resolver)

    def resolveWaiter(self, resolver):
        resolver.resolve(ProcessExitInformation(*self.exit_and_signal))

    def makeWaiter(self):
        p, r = makePromise()
        if self.exit_and_signal != self.EMPTY_EXIT_AND_SIGNAL:
            self.resolveWaiter(r)
        else:
            self.resolvers.append(r)
        return p

    def toString(self):
        if self.pid == self.EMPTY_PID:
            return u"<child process (unspawned)>"
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

        if atom is WAIT_0:
            return self.makeWaiter()

        raise Refused(self, atom, args)


@autohelp
@audited.DF
class makeProcess(Object):
    """
    Create a subordinate process on the current node from the given
    executable, arguments, and environment.

    `=> stdinFount`, if not null, will be treated as a fount and it will be
    flowed to a drain representing stdin. `=> stdoutDrain` and
    `=> stderrDrain` are similar but should be drains which will have founts
    flowed to them.
    """

    def recvNamed(self, atom, args, namedArgs):
        if atom is RUN_3:
            # Fourth incarnation: Now with stdio hookups.
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

            # Set up the list of streams. Note that, due to (not incorrect)
            # libuv behavior, we must wait for the subprocess to be spawned
            # before we can interact with the pipes that we are creating; to
            # do this, we'll have a list of the (f, d) pairs that we need to
            # start, and we'll ensure that that doesn't happen until after the
            # process has spawned.
            streams = []
            fount = namedArgs.extractStringKey(u"stdinFount", None)
            if fount is None:
                streams.append(nullptr(ruv.stream_t))
            else:
                stream = ruv.rffi.cast(ruv.stream_tp,
                                       ruv.alloc_pipe(vat.uv_loop))
                streams.append(stream)
                drain = StreamDrain(stream, vat)
                vat.sendOnly(fount, FLOWTO_1, [drain], EMPTY_MAP)
            for name in [u"stdoutDrain", u"stderrDrain"]:
                drain = namedArgs.extractStringKey(name, None)
                if drain is None:
                    streams.append(nullptr(ruv.stream_t))
                else:
                    stream = ruv.rffi.cast(ruv.stream_tp,
                                           ruv.alloc_pipe(vat.uv_loop))
                    streams.append(stream)
                    fount = StreamFount(stream, vat)
                    vat.sendOnly(fount, FLOWTO_1, [drain], EMPTY_MAP)

            try:
                process = ruv.allocProcess()
                sub = SubProcess(vat, process, argv, env)
                ruv.spawn(vat.uv_loop, process,
                          file=executable, args=argv, env=packedEnv,
                          streams=streams)
                sub.retrievePID()
                return sub
            except ruv.UVError as uve:
                raise userError(u"makeProcess: Couldn't spawn process: %s" %
                                uve.repr().decode("utf-8"))
        val = self.mirandaMethods(atom, args, namedArgs)
        if val is None:
            raise Refused(self, atom, args)
        else:
            return val
