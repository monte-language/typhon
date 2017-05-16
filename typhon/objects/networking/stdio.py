from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.log import deprecated
from typhon.objects.files import FileFount, FileDrain
from typhon.objects.networking.streams import StreamDrain, StreamFount
from typhon.objects.networking.streamcaps import (FileSink, FileSource,
                                                  StreamSink, TTYSink,
                                                  TTYSource)
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat


RUN_0 = getAtom(u"run", 0)


@runnable(RUN_0)
@deprecated(u"makeStdIn.run/0: Founts are deprecated")
def makeStdIn():
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    stdinKind = ruv.guess_handle(0)
    if stdinKind == ruv.HANDLE_TTY:
        stdin = ruv.alloc_tty(uv_loop, 0, True)
        return StreamFount(ruv.rffi.cast(ruv.stream_tp, stdin), vat)
    else:
        return FileFount(ruv.alloc_fs(), 0, vat)


@runnable(RUN_0)
@deprecated(u"makeStdOut.run/0: Founts are deprecated")
def makeStdOut():
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    stdoutKind = ruv.guess_handle(1)
    if stdoutKind == ruv.HANDLE_TTY:
        tty = ruv.alloc_tty(uv_loop, 1, False)
        # XXX works exactly as expected, including disabling most TTY signal
        # generation
        # ruv.TTYSetMode(tty, ruv.TTY_MODE_RAW)
        return StreamDrain(ruv.rffi.cast(ruv.stream_tp, tty), vat)
    else:
        return FileDrain(ruv.alloc_fs(), 1, vat)


@runnable(RUN_0)
@deprecated(u"makeStdErr.run/0: Founts are deprecated")
def makeStdErr():
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    stderrKind = ruv.guess_handle(2)
    if stderrKind == ruv.HANDLE_TTY:
        tty = ruv.alloc_tty(uv_loop, 2, False)
        # ruv.TTYSetMode(tty, ruv.TTY_MODE_RAW)
        return StreamDrain(ruv.rffi.cast(ruv.stream_tp, tty), vat)
    else:
        return FileDrain(ruv.alloc_fs(), 2, vat)


@autohelp
class stdio(Object):
    """
    A producer of streamcaps for the ancient standard I/O bytestreams.
    """

    @method("Any")
    def stdin(self):
        vat = currentVat.get()
        uv_loop = vat.uv_loop
        kind = ruv.guess_handle(0)
        if kind == ruv.HANDLE_TTY:
            stdin = ruv.alloc_tty(uv_loop, 0, True)
            stream = ruv.wrapStream(ruv.rffi.cast(ruv.stream_tp, stdin), 1)
            return TTYSource(stdin, stream, vat)
        else:
            return FileSource(0, vat)

    @method("Any")
    def stdout(self):
        vat = currentVat.get()
        uv_loop = vat.uv_loop
        kind = ruv.guess_handle(1)
        if kind == ruv.HANDLE_TTY:
            stdout = ruv.alloc_tty(uv_loop, 1, False)
            stream = ruv.wrapStream(ruv.rffi.cast(ruv.stream_tp, stdout), 1)
            return TTYSink(stdout, stream, vat)
        else:
            return FileSink(1, vat)

    @method("Any")
    def stderr(self):
        vat = currentVat.get()
        uv_loop = vat.uv_loop
        kind = ruv.guess_handle(2)
        if kind == ruv.HANDLE_TTY:
            stderr = ruv.alloc_tty(uv_loop, 2, False)
            stream = ruv.wrapStream(ruv.rffi.cast(ruv.stream_tp, stderr), 1)
            return TTYSink(stderr, stream, vat)
        else:
            return FileSink(2, vat)
