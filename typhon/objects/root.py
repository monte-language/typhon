# encoding: utf-8

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

import inspect

from rpython.rlib import rgc
from rpython.rlib.unroll import unrolling_iterable
from rpython.rlib.jit import jit_debug, promote, unroll_safe
from rpython.rlib.objectmodel import compute_identity_hash, specialize
from rpython.rlib.rstackovf import StackOverflow, check_stack_overflow

from typhon.atoms import getAtom
from typhon.errors import Refused, UserException, userError
from typhon.profile import profileTyphon


RUN_1 = getAtom(u"run", 1)
_CONFORMTO_1 = getAtom(u"_conformTo", 1)
_GETALLEGEDINTERFACE_0 = getAtom(u"_getAllegedInterface", 0)
_PRINTON_1 = getAtom(u"_printOn", 1)
_RESPONDSTO_2 = getAtom(u"_respondsTo", 2)
_SEALEDDISPATCH_1 = getAtom(u"_sealedDispatch", 1)
_UNCALL_0 = getAtom(u"_uncall", 0)
_WHENMORERESOLVED_1 = getAtom(u"_whenMoreResolved", 1)


mirandaAtoms = [
    _CONFORMTO_1,
    _GETALLEGEDINTERFACE_0,
    _PRINTON_1,
    _RESPONDSTO_2,
    _SEALEDDISPATCH_1,
    _UNCALL_0,
    _WHENMORERESOLVED_1,
]


def addTrail(ue, target, atom, args):
    argStringList = []
    for arg in args:
        try:
            s = arg.toQuote()
        except UserException as ue2:
            s = u"<**object throws %r when printed**>" % ue2
        if len(s) > 40:
            s = s[:39] + u"…"
        argStringList.append(s)
    argString = u", ".join(argStringList)
    ue.trail.append(u"In %s.%s(%s):" % (target.toQuote(), atom.verb,
                                        argString))

class Object(object):
    """
    A Monte object.
    """

    _immutable_fields_ = "_samenessHash?",

    _samenessHash = False, 0

    def __repr__(self):
        return self.toQuote().encode("utf-8")

    def toQuote(self):
        return self.toString()

    # @specialize.argtype(0)
    def toString(self):
        return u"<%s>" % self.__class__.__name__.decode("utf-8")

    def sizeOf(self):
        """
        The number of bytes occupied by this object.

        The default implementation will nearly always suffice unless some
        private data is attached to the object. Private data should only be
        accounted if it does not reference any Monte-visible object.
        """

        return rgc.get_rpy_memory_usage(self)

    def computeHash(self, depth):
        """
        Compute the sameness hash.

        This is the correct method to override to customize the sameness hash.

        Transparent objects are expected to customize their sameness hash.

        The `depth` parameter controls how many levels of structural recursion
        a nested object should include in the hash.
        """
        from typhon.objects.auditors import selfless, transparentStamp
        stamps = self.auditorStamps()
        if selfless in stamps and transparentStamp in stamps:
            return self.call(u"_uncall", []).computeHash(depth)
        # Here, if it existed, would lie Semitransparent hashing.
        return compute_identity_hash(self)

    def samenessHash(self):
        """
        The sameness hash for this object's settled state.

        If two objects are equal, then their sameness hash will be equal.
        """

        hashed, samenessHash = self._samenessHash

        if not hashed:
            self._samenessHash = _, samenessHash = True, self.computeHash(7)
        return samenessHash

    def call(self, verb, arguments, namedArgs=None):
        """
        Pass a message immediately to this object.
        """
        from typhon.objects.collections.maps import EMPTY_MAP
        if namedArgs is None:
            namedArgs = EMPTY_MAP
        arity = len(arguments)
        atom = getAtom(verb, arity)
        return self.callAtom(atom, arguments, namedArgs)

    def callAtom(self, atom, arguments, namedArgsMap):
        """
        This method is used to reuse atoms without having to rebuild them.
        """
        # Promote the atom, on the basis that atoms are generally reused.
        atom = promote(atom)
        # Log the atom to the JIT log. Don't do this if the atom's not
        # promoted; it'll be slow.
        jit_debug(atom.repr)

        try:
            return self.recvNamed(atom, arguments, namedArgsMap)
        except Refused as r:
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

    def mirandaMethods(self, atom, arguments, namedArgsMap):
        from typhon.objects.collections.maps import EMPTY_MAP
        if atom is _CONFORMTO_1:
            # Welcome to _conformTo/1.
            # to _conformTo(_): return self
            return self

        if atom is _GETALLEGEDINTERFACE_0:
            # Welcome to _getAllegedInterface/0.
            interface = self.optInterface()
            if interface is None:
                from typhon.objects.interfaces import ComputedInterface
                interface = ComputedInterface(self)
            return interface

        if atom is _PRINTON_1:
            # Welcome to _printOn/1.
            from typhon.objects.constants import NullObject
            self.printOn(arguments[0])
            return NullObject

        if atom is _RESPONDSTO_2:
            from typhon.objects.constants import wrapBool
            from typhon.objects.data import unwrapInt, unwrapStr
            verb = unwrapStr(arguments[0])
            arity = unwrapInt(arguments[1])
            atom = getAtom(verb, arity)
            result = (atom in self.respondingAtoms() or
                      atom in mirandaAtoms)
            return wrapBool(result)

        if atom is _SEALEDDISPATCH_1:
            # to _sealedDispatch(_): return null
            from typhon.objects.constants import NullObject
            return NullObject

        if atom is _UNCALL_0:
            from typhon.objects.constants import NullObject
            return NullObject

        if atom is _WHENMORERESOLVED_1:
            # Welcome to _whenMoreResolved.
            # This method's implementation, in Monte, should be:
            # to _whenMoreResolved(callback): callback<-(self)
            from typhon.vats import currentVat
            vat = currentVat.get()
            vat.sendOnly(arguments[0], RUN_1, [self], EMPTY_MAP)
            from typhon.objects.constants import NullObject
            return NullObject
        return None

    def recvNamed(self, atom, args, namedArgs):
        try:
            return self.recv(atom, args)
        except Refused:
            val = self.mirandaMethods(atom, args, namedArgs)
            if val is None:
                raise
            else:
                return val

    def recv(self, atom, args):
        raise Refused(self, atom, args)

    # Auditors.

    def auditorStamps(self):
        from typhon.objects.collections.helpers import emptySet
        return emptySet

    @unroll_safe
    @profileTyphon("_auditedBy.run/2")
    def auditedBy(self, prospect):
        """
        Whether a prospective stamp has been left on this object.
        """

        # The number of different objects that will pass through here is
        # surprisingly low; consider how Python would look if metaclasses were
        # promoted.
        prospect = promote(prospect)

        return prospect in self.auditorStamps()

    def optInterface(self):
        return None

    # Eventuality.

    def isSettled(self, sofar=None):
        """
        Whether this object is currently settled.

        Objects may not unsettle themselves; once this method starts returning
        True, it must not change to False.

        `sofar`, if not None, is a dictionary of Objects to None (a set),
        where all keys have been determined settled.
        """

        # This was a *difficult* decision. Sorry.
        return True

    # Pretty-printing.

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
        return {}


@specialize.call_location()
def runnable(singleAtom=None, _stamps=[]):
    """
    Promote a function to a Monte object type.

    The resulting class object can be called multiple times to create multiple
    Monte objects.

    If you don't provide an atom, then I will guess based on the arity of the
    passed-in function and the function's name.
    """

    def inner(f):
        name = f.__name__.decode("utf-8")
        doc = f.__doc__.decode("utf-8") if f.__doc__ else None

        if singleAtom is None:
            arity = len(inspect.getargspec(f).args)
            theAtom = getAtom(name, arity)
        else:
            arity = singleAtom.arity
            theAtom = singleAtom
        unrolledArity = unrolling_iterable(range(arity))

        class runnableObject(Object):

            def toString(self):
                return u"<%s>" % name

            def auditorStamps(self):
                from typhon.objects.collections.helpers import asSet
                return asSet(_stamps)

            def isSettled(self, sofar=None):
                return True

            def docString(self):
                return doc

            def respondingAtoms(self):
                return {theAtom: doc}

            def recv(self, atom, listArgs):
                if atom is theAtom:
                    args = ()
                    for i in unrolledArity:
                        args += (listArgs[i],)
                    return f(*args)
                else:
                    raise Refused(self, atom, listArgs)

        return runnableObject

    return inner


class audited(object):
    """
    Helper for annotating objects with prebuilt auditor stamps.

    This annotation is equivalent to the committer saying "Yes, I read through
    the source code of this object, and it's fine, really."
    """

    @staticmethod
    def DF(cls):
        def auditorStamps(self):
            from typhon.objects.auditors import deepFrozenStamp
            from typhon.objects.collections.helpers import asSet
            return asSet([deepFrozenStamp])
        cls.auditorStamps = auditorStamps
        return cls

    @staticmethod
    def DFSelfless(cls):
        def auditorStamps(self):
            from typhon.objects.auditors import deepFrozenStamp, selfless
            from typhon.objects.collections.helpers import asSet
            return asSet([deepFrozenStamp, selfless])
        cls.auditorStamps = auditorStamps
        return cls

    @staticmethod
    def DFTransparent(cls):
        def auditorStamps(self):
            from typhon.objects.auditors import (deepFrozenStamp, selfless,
                                                 transparentStamp)
            from typhon.objects.collections.helpers import asSet
            return asSet([deepFrozenStamp, selfless, transparentStamp])
        cls.auditorStamps = auditorStamps
        return cls

    @staticmethod
    def Selfless(cls):
        def auditorStamps(self):
            from typhon.objects.auditors import selfless
            from typhon.objects.collections.helpers import asSet
            return asSet([selfless])
        cls.auditorStamps = auditorStamps
        return cls

    @staticmethod
    def Transparent(cls):
        def auditorStamps(self):
            from typhon.objects.auditors import selfless, transparentStamp
            from typhon.objects.collections.helpers import asSet
            return asSet([selfless, transparentStamp])
        cls.auditorStamps = auditorStamps
        return cls
