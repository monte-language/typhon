# Copyright (C) 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

from rpython.rlib.jit import unroll_safe

from typhon.errors import Ejecting, Refused, UserException
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.collections import ConstList
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector
from typhon.objects.printers import Printer
from typhon.objects.root import Object
from typhon.objects.slots import Binding, FinalSlot
from typhon.smallcaps.machine import SmallCaps


class ScriptObject(Object):

    _immutable_fields_ = "codeScript", "globals[*]", "closure[*]"

    def __init__(self, codeScript, globals, closure, displayName, stamps):
        self.codeScript = codeScript
        self.globals = globals
        self.closure = closure
        self.displayName = displayName
        self.stamps = stamps

        # Make sure that we can access ourselves.
        self.patchSelf()

    def patchSelf(self):
        selfIndex = self.codeScript.selfIndex()
        if selfIndex != -1:
            self.closure[selfIndex] = Binding(FinalSlot(self))

    def auditedBy(self, stamp):
        return wrapBool(stamp in self.stamps)

    def toString(self):
        try:
            printer = Printer()
            self.call(u"_printOn", [printer])
            return printer.value()
        except Refused:
            return u"<%s>" % self.displayName
        except UserException, e:
            return u"<%s (threw exception %s when printed)>" % (self.displayName, e.error())

    toQuote = toString

    @unroll_safe
    def recv(self, atom, args):
        code = self.codeScript.lookupMethod(atom)
        if code is None:
            # No atoms matched, so there's no prebuilt methods. Instead, we'll
            # use our matchers.
            for matcher in self.codeScript.matchers:
                with Ejector() as ej:
                    machine = SmallCaps(matcher, self.closure, self.globals)
                    machine.push(ConstList([StrObject(atom.verb),
                                            ConstList(args)]))
                    machine.push(ej)
                    try:
                        machine.run()
                        return machine.pop()
                    except Ejecting as e:
                        if e.ejector is ej:
                            # Looks like unification failed. On to the next
                            # matcher!
                            continue
                        else:
                            # It's not ours, cap'n.
                            raise

            raise Refused(self, atom, args)

        machine = SmallCaps(code, self.closure, self.globals)
        # print "--- Running", self.displayName, atom, args
        # Push the arguments onto the stack, backwards.
        for arg in reversed(args):
            machine.push(arg)
            machine.push(NullObject)
        machine.run()
        return machine.pop()
