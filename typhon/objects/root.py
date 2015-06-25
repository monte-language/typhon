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
from rpython.rlib.objectmodel import compute_identity_hash, specialize
from rpython.rlib.rstackovf import StackOverflow, check_stack_overflow

from typhon.atoms import getAtom
from typhon.errors import Refused, UserException, userError


RUN_1 = getAtom(u"run", 1)
_CONFORMTO_1 = getAtom(u"_conformTo", 1)
_PRINTON_1 = getAtom(u"_printOn", 1)
_RESPONDSTO_2 = getAtom(u"_respondsTo", 2)
_WHENMORERESOLVED_1 = getAtom(u"_whenMoreResolved", 1)


def addTrail(ue, target, atom, args):
    argStringList = []
    for arg in args:
        try:
            argStringList.append(arg.toQuote())
        except UserException as ue2:
            argStringList.append(u"<**object throws %r when printed**>" % ue2)
    argString = u", ".join(argStringList)
    atomRepr = atom.repr.decode("utf-8")
    ue.trail.append(u"In %s.%s [%s]:" % (target.toQuote(), atomRepr,
                                         argString))


class Object(object):

    # The attributes that all Objects have in common.
    _attrs_ = "stamps",

    # The attributes that are not mutable.
    _immutable_fields_ = "stamps",

    # The auditor stamps on objects.
    stamps = []

    def __repr__(self):
        return self.toQuote().encode("utf-8")

    def toQuote(self):
        return self.toString()

    # @specialize.argtype(0)
    def toString(self):
        return u"<%s>" % self.__class__.__name__.decode("utf-8")

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
        except Refused as r:
            # This block of method implementations is Typhon's Miranda
            # protocol. ~ C.

            if atom is _CONFORMTO_1:
                # Welcome to _conformTo/1.
                # to _conformTo(_): return self
                return self

            if atom is _PRINTON_1:
                # Welcome to _printOn/1.
                return self.printOn(arguments[0])

            if atom is _RESPONDSTO_2:
                from typhon.objects.constants import wrapBool
                from typhon.objects.data import unwrapInt, unwrapStr
                verb = unwrapStr(arguments[0])
                arity = unwrapInt(arguments[1])
                atom = getAtom(verb, arity)
                return wrapBool(atom in self.respondingAtoms())

            if atom is _WHENMORERESOLVED_1:
                # Welcome to _whenMoreResolved.
                # This method's implementation, in Monte, should be:
                # to _whenMoreResolved(callback): callback<-(self)
                from typhon.vats import currentVat
                vat = currentVat.get()
                vat.sendOnly(arguments[0], RUN_1, [self])
                from typhon.objects.constants import NullObject
                return NullObject

            addTrail(r, self, atom, arguments)
            raise

        except UserException as ue:
            addTrail(ue, self, atom, arguments)
            raise
        except MemoryError:
            ue = userError(u"Memory corruption or exhausted heap")
            addTrail(ue, self, atom, arguments)
            raise ue
        except StackOverflow:
            check_stack_overflow()
            ue = userError(u"Stack overflow")
            addTrail(ue, self, atom, arguments)
            raise ue

    def recv(self, atom, args):
        raise Refused(self, atom, args)

    def auditedBy(self, stamp):
        return stamp in self.stamps

    def printOn(self, printer):
        # Note that the printer is a Monte-level object.
        from typhon.objects.data import StrObject
        printer.call(u"print", [StrObject(self.toString())])

    # Documentation/help stuff.

    def docString(self):
        doc = self.__class__.__doc__
        if doc is not None:
            return doc.decode("utf-8")
        return None

    def respondingAtoms(self):
        return []


def runnable(singleAtom, _stamps=[]):
    """
    Promote a function to a Monte object type.

    The resulting class object can be called multiple times to create multiple
    Monte objects.
    """

    def inner(f):
        name = u"<%s>" % f.__name__.decode("utf-8")
        doc = f.__doc__.decode("utf-8") if f.__doc__ else None

        class runnableObject(Object):
            stamps = _stamps

            def toString(self):
                return name

            def docString(self):
                return doc

            def respondingAtoms(self):
                return [singleAtom]

            def recv(self, atom, args):
                if atom is singleAtom:
                    return f(args)
                raise Refused(self, atom, args)

        return runnableObject

    return inner
