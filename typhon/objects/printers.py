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

from rpython.rlib.rstring import UnicodeBuilder

from typhon.autohelp import autohelp, method
from typhon.errors import UserException
from typhon.objects.data import CharObject, StrObject, unwrapStr
from typhon.objects.refs import Promise, isBroken, resolution
from typhon.objects.root import Object
from typhon.profile import profileTyphon


@autohelp
class Printer(Object):
    """
    An object which can be printed to.
    """

    def __init__(self, ub=None, newline=StrObject(u"\n"), context=None):
        self.ub = ub or UnicodeBuilder()
        self.newline = newline
        if context is None:
            self.context = {}
        else:
            self.context = context

    def toString(self):
        return u"<printer>"

    @method("Any", "Any")
    def indent(self, morePrefix):
        return Printer(self.ub, self.newline.call(u"add", [morePrefix]),
                       self.context)

    @method("Void", "Any")
    def println(self, obj):
        self._print(obj)
        self._print(self.newline)

    @method("Void", "Any")
    def lnPrint(self, obj):
        self._print(self.newline)
        self._print(obj)

    @method.py("Void", "Any", _verb="print")
    @profileTyphon("Printer.print/1")
    def _print(self, item):
        item = resolution(item)
        if isinstance(item, StrObject):
            self.ub.append(unwrapStr(item))
        else:
            self.objPrint(item)

    @method("Void", "Any")
    def quote(self, item):
        item = resolution(item)
        if isinstance(item, CharObject) or isinstance(item, StrObject):
            self.ub.append(item.toQuote())
        else:
            self.objPrint(item)

    @profileTyphon("Printer.quote/1")
    def objPrint(self, item):
        item = resolution(item)
        if isinstance(item, Promise) and isBroken(item):
            if item._problem in self.context:
                self.ub.append(u"<Ref broken by: **CYCLE**>")
            else:
                self.ub.append(item.toString())
        elif isinstance(item, Promise) and not item.isResolved():
            self.ub.append(u"<promise>")
        elif isinstance(item, Promise):
            # probably a far ref of some kind
            self.ub.append(item.toString())
        elif item in self.context:
            self.ub.append(u"<**CYCLE**>")
        else:
            self.context[item] = None
            try:
                item.call(u"_printOn", [self])
            except UserException, e:
                self.ub.append(u"<** %s throws %s when printed**>" % (
                    item.toString(), e.error()))
            del self.context[item]

    def printStr(self, s):
        self.ub.append(s)

    def value(self):
        return self.ub.build()


def toString(self):
    try:
        printer = Printer()
        printer.objPrint(self)
        return printer.value()
    except UserException, e:
        return u"<%s (threw exception %s when printed)>" % (
            self.__class__.__name__.decode('utf-8'),
            e.error())
