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


class UserException(Exception):
    """
    An error occurred in user code.
    """

    def __init__(self, payload):
        self.payload = payload
        self.trail = []

    def formatError(self):
        pieces = [self.error()] + self.trail
        pieces.append(u"Exception in user code:")
        pieces.reverse()
        return u"\n".join(pieces).encode("utf-8")

    def error(self):
        return u"Error: " + self.payload.toQuote()


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
        return (u"Message refused: (%s, %s, [%s])" %
                (self.target.toString(), self.atom.repr.decode("utf-8"),
                    args))


class WrongType(UserException):
    """
    An object was not unwrappable.
    """

    def __init__(self, message):
        self.message = message
        self.trail = []

    def error(self):
        return u"Object was wrong type: %s" % self.message
