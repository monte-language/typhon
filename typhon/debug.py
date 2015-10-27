from rpython.rlib.debug import debug_print

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
