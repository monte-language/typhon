from typhon import ruv
from typhon.atoms import getAtom
from typhon.objects.networking.streams import StreamDrain, StreamFount
from typhon.objects.root import runnable
from typhon.vats import currentVat


RUN_0 = getAtom(u"run", 0)


@runnable(RUN_0)
def makeStdIn():
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    tty = ruv.alloc_tty(uv_loop, 0, True)

    return StreamFount(ruv.rffi.cast(ruv.stream_tp, tty), vat)


@runnable(RUN_0)
def makeStdOut():
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    tty = ruv.alloc_tty(uv_loop, 1, False)
    # XXX works exactly as expected, including disabling most TTY signal
    # generation
    # ruv.TTYSetMode(tty, ruv.TTY_MODE_RAW)

    return StreamDrain(ruv.rffi.cast(ruv.stream_tp, tty), vat)


@runnable(RUN_0)
def makeStdErr():
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    tty = ruv.alloc_tty(uv_loop, 2, False)
    # ruv.TTYSetMode(tty, ruv.TTY_MODE_RAW)

    return StreamDrain(ruv.rffi.cast(ruv.stream_tp, tty), vat)
