"""
Hack to let us easily profile any portion of the VM which intersperses its
frames with frames of Monte user-level code.
"""

import inspect
import os.path

from rpython.rlib import rvmprof


profiledLocations = []

def registerProfileTyphon():
    """
    Register all profiling locations.

    Call this once from main.py, please.
    """

    for switch in profiledLocations:
        switch()


def profileTyphon(name):
    """
    A decorator to cause this method's frames to show up in vmprof logs.

    The method must not accept more than five arguments, including `self`, and
    all arguments must be instances or ints. In addition, the method cannot
    accept kwargs.
    """

    def deco(f):
        # Prepare the full location name.
        lineNo = inspect.getsourcelines(f)[1]
        moduleName = os.path.basename(inspect.getsourcefile(f))
        fullLocation = "ty:%s:%d:%s" % (f.__name__, lineNo, moduleName)

        # Produce the code object class.
        class FakeCodeObj(object):
            fullName = fullLocation

        rvmprof.register_code_object_class(FakeCodeObj,
                lambda obj: obj.fullName)

        # Prebuild one in order to have something to return.
        codeObj = FakeCodeObj()
        def get_code_fn(*args):
            return codeObj

        # And register it at runtime.
        def switch():
            rvmprof.register_code(codeObj, lambda obj: obj.fullName)
        profiledLocations.append(switch)

        @rvmprof.vmprof_execute_code(name, get_code_fn)
        def fakeExecuteCode(*args):
            return f(*args)

        return fakeExecuteCode
    return deco
