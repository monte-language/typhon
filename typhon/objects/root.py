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

from rpython.rlib.jit import jit_debug, promote
from rpython.rlib.objectmodel import compute_identity_hash

from typhon.atoms import getAtom
from typhon.errors import Refused


RUN_1 = getAtom(u"run", 1)
_CONFORMTO_1 = getAtom(u"_conformTo", 1)
_WHENMORERESOLVED_1 = getAtom(u"_whenMoreResolved", 1)


class Object(object):

    # The attributes that all Objects have in common.
    _attrs_ = "displayName", "stamps",

    # The attributes that are not mutable.
    _immutable_fields_ = "displayName",

    # The "display" name, used in fast/imprecise/classy debugging dumps.
    # Primary use of this attribute is for profiling.
    displayName = u"Object"

    # The auditor stamps on objects.
    stamps = []

    def __repr__(self):
        return self.toQuote().encode("utf-8")

    def toQuote(self):
        return self.toString()

    def toString(self):
        return u"<object>"

    def hash(self):
        """
        Create a conservative integer hash of this object.

        If two objects are equal, then they must hash equal.
        """

        return compute_identity_hash(self)

    def call(self, verb, arguments):
        """
        Pass a message immediately to this object.
        """

        arity = len(arguments)
        atom = getAtom(verb, arity)
        return self.callAtom(atom, arguments)

    def callAtom(self, atom, arguments):
        """
        This method is used to reuse atoms without having to rebuild them.
        """

        # Promote the atom, on the basis that atoms are generally reused.
        atom = promote(atom)
        # Log the atom to the JIT log. Don't do this if the atom's not
        # promoted; it'll be slow.
        jit_debug(atom.repr)

        try:
            return self.recv(atom, arguments)
        except:
            if atom is _CONFORMTO_1:
                # Welcome to _conformTo/1.
                # to _conformTo(_): return self
                return self
            if atom is _WHENMORERESOLVED_1:
                # Welcome to _whenMoreResolved.
                # This method's implementation, in Monte, should be:
                # to _whenMoreResolved(callback): callback<-(self)
                from typhon.vats import currentVat
                vat = currentVat.get()
                vat.sendOnly(arguments[0], RUN_1, [self])
                from typhon.objects.constants import NullObject
                return NullObject
            raise

    def recv(self, atom, args):
        raise Refused(self, atom, args)


def runnable(singleAtom):
    """
    Promote a function to a Monte object type.

    The resulting class object can be called multiple times to create multiple
    Monte objects.
    """

    def inner(f):
        name = f.__name__.decode("utf-8")

        class runnableObject(Object):
            displayName = name

            def toString(self):
                return u"<%s>" % name

            def recv(self, atom, args):
                if atom is singleAtom:
                    return f(args)
                raise Refused(self, atom, args)

        return runnableObject

    return inner
