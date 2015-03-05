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

from rpython.rlib.jit import elidable


class Atom(object):
    """
    A verb and arity.

    Only compare by identity.
    """

    _immutable_ = True

    def __init__(self, verb, arity):
        self.verb = verb
        self.arity = arity
        self.repr = "Atom(%s/%d)" % (self.verb.encode("utf-8"), self.arity)

    def __repr__(self):
        return self.repr


class _AtomHolder(object):

    _immutable_ = True

    def __init__(self):
        self.atoms = {}

    @elidable
    def getAtom(self, verb, arity):
        """
        Return the one and only atom for a given verb and arity.

        Idempotent and safe to call at both translation and runtime.
        """

        key = verb, arity
        if key not in self.atoms:
            self.atoms[key] = Atom(verb, arity)
        return self.atoms[key]


getAtom = _AtomHolder().getAtom
