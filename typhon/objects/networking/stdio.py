from typhon import ruv
from typhon.autohelp import autohelp, method
from typhon.objects.networking.streamcaps import (FileSink, FileSource,
                                                  TTYSink, TTYSource)
from typhon.objects.root import Object
from typhon.vats import currentVat


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
