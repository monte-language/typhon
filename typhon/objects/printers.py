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

from typhon.atoms import getAtom
from typhon.errors import Refused
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapStr
from typhon.objects.root import Object


PRINT_1 = getAtom(u"print", 1)


class Printer(Object):
    """
    An object which can be printed to.
    """

    def __init__(self):
        self.ub = UnicodeBuilder()

    def toString(self):
        return u"<printer>"

    def recv(self, atom, args):
        if atom is PRINT_1:
            self.ub.append(unwrapStr(args[0]))
            return NullObject

        raise Refused(atom, args)

    def value(self):
        return self.ub.build()
