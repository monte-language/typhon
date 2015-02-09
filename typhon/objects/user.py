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

from rpython.rlib.jit import elidable, promote, unroll_safe

from typhon.atoms import getAtom
from typhon.errors import Ejecting, Refused
from typhon.objects.constants import NullObject
from typhon.objects.collections import ConstList
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector
from typhon.objects.printers import Printer
from typhon.objects.root import Object
from typhon.smallcaps import SmallCaps


class ScriptObject(Object):

    def __init__(self, codeScript, closure, displayName):
        self.codeScript = codeScript
        self.closure = {}
        closureNames = self.codeScript.closureNames.keys()
        for i in range(len(closureNames)):
            self.closure[closureNames[i]] = closure[i]
        self.displayName = displayName

    def patchSelf(self, binding):
        if self.displayName in self.codeScript.closureNames:
            self.closure[self.displayName] = binding

    def toString(self):
        try:
            printer = Printer()
            self.call(u"_printOn", [printer])
            return printer.value()
        except Refused:
            return u"<%s>" % self.displayName

    @unroll_safe
    def recv(self, atom, args):
        code = self.codeScript.methods.get(atom, None)
        if code is None:
            # No atoms matched, so there's no prebuilt methods. Instead, we'll
            # use our matchers.
            for matcher in self.codeScript.matchers:
                with Ejector() as ej:
                    frame = {}
                    for key in matcher.frame:
                        frame[key] = self.closure[key]

                    machine = SmallCaps(matcher, frame)
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

        frame = {}
        for key in code.frame:
            frame[key] = self.closure[key]

        machine = SmallCaps(code, frame)
        # print "--- Running", self.displayName, atom, args
        # Push the arguments onto the stack, backwards.
        args.reverse()
        for arg in args:
            machine.push(arg)
            # XXX is this the right ejector?
            machine.push(NullObject)
        machine.run()
        return machine.pop()
