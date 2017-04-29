from rpython.rlib.rarithmetic import intmask

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.objects.root import Object
from typhon.objects.collections.maps import EMPTY_MAP
from typhon.objects.data import IntObject

from typhon.ruv import (alloc_signal, free, SignalStart, SignalStop,
                        stashSignal, unstashSignal, unstashingSignal)

RUN_1 = getAtom(u"run", 1)


def _signalCB(signal, signum):
    with unstashingSignal(signal) as (vat, handle):
        vat.sendOnly(handle._target, RUN_1, [IntObject(intmask(signum))],
                     EMPTY_MAP)


@autohelp
class SignalHandle(Object):
    def __init__(self, signum, target, vat):
        self._signum = signum
        self._target = target
        self._vat = vat
        self._signal = alloc_signal(vat.uv_loop)
        SignalStart(self._signal, _signalCB, self._signum)
        stashSignal(self._signal, (vat, self))

    @method("Void")
    def disarm(self):
        unstashSignal(self._signal)
        SignalStop(self._signal)
        free(self._signal)
