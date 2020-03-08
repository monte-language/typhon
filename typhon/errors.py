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


class Ejecting(Exception):
    """
    An ejector is currently being used.
    """

    def __init__(self, ejector, value):
        self.ejector = ejector
        self.value = value


class LoadFailed(Exception):
    """
    An AST couldn't be loaded.
    """


def printObjTerse(obj):
    try:
        s = obj.toQuote()
    except UserException as ue2:
        s = u"<**object throws %r when printed**>" % ue2

    if len(s) > 40:
        s = s[:39] + u"…"

    return s


class UserException(Exception):
    """
    An error occurred in user code.
    """

    def __init__(self, payload):
        from typhon.objects.exceptions import SealedException
        if isinstance(payload, SealedException):
            self.payload = payload.ue.getPayload()
            self.trail = payload.ue.trail
        else:
            self.payload = payload
            self.trail = []

    def __str__(self):
        return self.formatError().encode("utf-8")

    def formatError(self):
        pieces = [self.error()] + self.formatTrail()
        pieces.append(u"Exception in user code:")
        pieces.reverse()
        return u"\n".join(pieces).encode("utf-8")

    def error(self):
        return u"Error: " + self.payload.toQuote()

    def getPayload(self):
        return self.payload

    def addTrail(self, target, atom, args, span):
        """
        Add a traceback frame to this exception.
        """

        self.trail.append((target, atom, args, span))

    def formatTrail(self):
        rv = []
        for target, atom, args, span in self.trail:
            argStringList = [printObjTerse(arg) for arg in args]
            argString = u", ".join(argStringList)
            if span is None:
                spanStr = u""
            else:
                spanStr = u" %s:%s::%s:%s" % (
                    str(span.startLine).decode('utf-8'),
                    str(span.startCol).decode('utf-8'),
                    str(span.endLine).decode('utf-8'),
                    str(span.endCol).decode('utf-8'))
            rv.append(u"  %s.%s(%s)" % (printObjTerse(target), atom.verb,
                                        argString))
            path, name = target.getFQN().split(u"$", 1)
            rv.append(u"File '%s'%s, in object %s:" % (path, spanStr, name))
        return rv


def userError(s):
    from typhon.objects.data import StrObject
    return UserException(StrObject(s))


class Refused(UserException):
    """
    An object refused to accept a message passed to it.
    """

    def __init__(self, target, atom, args):
        self.target = target
        self.atom = atom
        self.args = args
        self.trail = []

    def error(self):
        l = []
        for arg in self.args:
            if arg is None:
                l.append(u"None")
            else:
                l.append(arg.toQuote())
        args = u", ".join(l)
        return (u"Message refused: (%s).%s(%s)" %
                (self.target.toString(), self.atom.verb, args))

    def getPayload(self):
        from typhon.objects.data import StrObject
        return StrObject(self.error())


class WrongType(UserException):
    """
    An object was not unwrappable.
    """

    def __init__(self, message):
        self.message = message
        self.trail = []

        from typhon.objects.data import StrObject
        self.payload = StrObject(u"Object had incorrect type")

    def error(self):
        return u"Object was wrong type: %s" % self.message

    def getPayload(self):
        from typhon.objects.data import StrObject
        return StrObject(self.error())
