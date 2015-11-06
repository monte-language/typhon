from rpython.rlib.debug import debug_print
from rpython.rlib.jit import JitHookInterface

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
        debugPrint("Aborted trace:", greenkey_repr, reason, "operations",
                   str(len(operations)))

    def after_compile(self, debug_info):
        debugPrint("Compiled:", debug_info.get_greenkey_repr(), "operations",
                   str(len(debug_info.operations)))

    def after_compile_bridge(self, debug_info):
        debugPrint("Compiled bridge: operations",
                   str(len(debug_info.operations)))
