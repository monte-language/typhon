# Copyright (C) 2015 Google Inc. All rights reserved.
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

from typhon.atoms import getAtom
from typhon.errors import Refused
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, StrObject, unwrapInt, unwrapStr
from typhon.objects.refs import makePromise
from typhon.objects.root import Object, runnable
from typhon.vats import Callable, currentVat


GETCONTENTS_0 = getAtom(u"getContents", 0)
SETCONTENTS_1 = getAtom(u"setContents", 1)
FLOWINGFROM_1 = getAtom(u"flowingFrom", 1)
FLOWSTOPPED_1 = getAtom(u"flowStopped", 1)
FLOWTO_1 = getAtom(u"flowTo", 1)
PAUSEFLOW_0 = getAtom(u"pauseFlow", 0)
RECEIVE_1 = getAtom(u"receive", 1)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
STOPFLOW_0 = getAtom(u"stopFlow", 0)
UNPAUSE_0 = getAtom(u"unpause", 0)


class FileUnpauser(Object):
    """
    A pause on a file fount.
    """

    def __init__(self, fount):
        self.fount = fount

    def recv(self, atom, args):
        if atom is UNPAUSE_0:
            if self.fount is not None:
                self.fount.unpause()
                self.fount = None
            return NullObject

        raise Refused(self, atom, args)


class FileFount(Object):

    def __init__(self, handle):
        self.handle = handle

    def recv(self, atom, args):
        if atom is FLOWTO_1:
            self.drain = drain = args[0]
            rv = drain.call(u"flowingFrom", [self])
            return rv

        if atom is PAUSEFLOW_0:
            return self.pause()

        if atom is STOPFLOW_0:
            vat = currentVat.get()
            vat.afterTurn(self.close)
            return NullObject

        raise Refused(self, atom, args)

    def close(self):
        self.handle.close()
        if self.drain is not None:
            vat = currentVat.get()
            vat.sendOnly(self.drain, u"flowStopped",
                         [StrObject(u"End of file")])

    def pause(self):
        self.pauses += 1
        return FileUnpauser(self)

    def unpause(self):
        self.pauses -= 1
        vat = currentVat.get()
        vat.afterTurn(self.read)

    def read(self):
        # XXX What do you know about POSIX and file systems? This function is
        # totally wrong and the wrongness isn't removable without
        # rearchitecting a fair amount of reactor code. I apologize for doing
        # it this way, but it is non-trivial and I don't know how I would fix
        # it at this point in time. ~ C.
        if not self.pauses and self.drain is not None:
            # 16KiB reads. There is no justification for this; 4KiB seemed too
            # small and 1MiB seemed too large.
            buf = self.handle.read(16384)
            rv = [IntObject(ord(byte)) for byte in buf]
            vat = currentVat.get()
            vat.sendOnly(self.drain, u"receive", [ConstList(rv)])

            if len(buf) < 16384:
                # Short read; this will be the last chunk.
                vat.afterTurn(self.close)
            else:
                vat.afterTurn(self.read)


class FileDrain(Object):

    def __init__(self, handle):
        self.handle = handle

        self.chunks = []

    def recv(self, atom, args):
        if atom is FLOWINGFROM_1:
            return self

        if atom is RECEIVE_1:
            data = unwrapList(args[0])
            s = "".join([chr(unwrapInt(byte)) for byte in data])

            # If this is the first time that we've received since last flush,
            # then prepare to flush after the turn.
            if not self.chunks:
                vat = currentVat.get()
                vat.afterTurn(self.flush)

            self.chunks.append(s)
            return NullObject

        if atom is FLOWSTOPPED_1:
            vat = currentVat.get()
            vat.afterTurn(self.close)
            return NullObject

        raise Refused(self, atom, args)

    def close(self):
        self.handle.close()

    def flush(self):
        for chunk in self.chunks:
            self.handle.write(chunk)

        # Reuse the allocated list; we'll probably use around the same number
        # of chunks per iteration.
        del self.chunks[:]


class GetContents(Callable):

    def __init__(self, path, resolver):
        self.path = path
        self.resolver = resolver

    def call(self):
        with open(self.path, "rb") as handle:
            s = handle.read()

        data = ConstList([IntObject(ord(c)) for c in s])
        self.resolver.resolve(data)


class SetContents(Callable):

    def __init__(self, path, data, resolver):
        self.path = path
        self.data = data
        self.resolver = resolver

    def call(self):
        with open(self.path, "wb") as handle:
            handle.write(self.data)

        self.resolver.resolve(NullObject)


class FileResource(Object):
    """
    A Resource which provides access to the file system of the current node.

    For help understanding this class, consult FilePath, the POSIX standards,
    and a bottle of your finest and strongest liquor. Perhaps not in that
    order, though.
    """

    _immutable_ = True

    def __init__(self, path):
        self.path = path

    def recv(self, atom, args):
        if atom is GETCONTENTS_0:
            p, r = makePromise()
            vat = currentVat.get()
            vat.afterTurn(GetContents(self.path, r))
            return p

        if atom is SETCONTENTS_1:
            l = unwrapList(args[0])
            data = "".join([chr(unwrapInt(i)) for i in l])

            p, r = makePromise()
            vat = currentVat.get()
            vat.afterTurn(SetContents(self.path, data, r))
            return p

        raise Refused(self, atom, args)


@runnable(RUN_1)
def makeFileResource(args):
    path = unwrapStr(args[0]).encode("utf-8")
    return FileResource(path)
