from typhon import ruv
from typhon.atoms import getAtom
from typhon.objects.networking.streams import StreamDrain, StreamFount
from typhon.objects.root import runnable
from typhon.vats import currentVat


RUN_0 = getAtom(u"run", 0)


@runnable(RUN_0)
def makeStdIn(_):
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    tty = ruv.alloc_tty(uv_loop, 0, True)

    return StreamFount(ruv.rffi.cast(ruv.stream_tp, tty), vat)


@runnable(RUN_0)
def makeStdOut(_):
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    tty = ruv.alloc_tty(uv_loop, 1, False)

    return StreamDrain(ruv.rffi.cast(ruv.stream_tp, tty), vat)


@runnable(RUN_0)
def makeStdErr(_):
    vat = currentVat.get()
    uv_loop = vat.uv_loop
    tty = ruv.alloc_tty(uv_loop, 2, False)

    return StreamDrain(ruv.rffi.cast(ruv.stream_tp, tty), vat)
