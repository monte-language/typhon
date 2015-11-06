from rpython.rlib.debug import debug_print
from rpython.rlib.jit import Counters, JitHookInterface

class DebugPrinter(object):

    _immutable_fields_ = "enabled?"

    enabled = False

    def enableDebugPrint(self):
        self.enabled = True

    def debugPrint(self, *args):
        if self.enabled:
            debug_print(*args)


debugPrinter = DebugPrinter()
debugPrint = debugPrinter.debugPrint
enableDebugPrint = debugPrinter.enableDebugPrint


class TyphonJitHooks(JitHookInterface):

    def on_abort(self, reason, jitdriver, greenkey, greenkey_repr, logops,
                 operations):
        if True:
            return
        reasonString = Counters.counter_names[reason]
        print "Aborted trace:", greenkey_repr, reasonString, "operations", len(operations)

    def after_compile(self, debug_info):
        if True:
            return
        print "Compiled:", debug_info.get_greenkey_repr(), "operations", len(debug_info.operations)

    def after_compile_bridge(self, debug_info):
        if True:
            return
        print "Compiled bridge: operations", len(debug_info.operations)
