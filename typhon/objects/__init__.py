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

from typhon.errors import Refused
from typhon.objects.constants import BoolObject, wrapBool
from typhon.objects.root import Object


class ScriptObject(Object):

    def __init__(self, script, env):
        self._env = env
        self._script = script
        self._methods = {}

        for method in self._script._methods:
            # God *dammit*, RPython.
            from typhon.nodes import Method
            assert isinstance(method, Method)
            assert isinstance(method._verb, unicode)
            self._methods[method._verb] = method

    def repr(self):
        return "<scriptObject>"

    def recv(self, verb, args):
        if verb in self._methods:
            method = self._methods[verb]

            with self._env as env:
                # Set up parameters from arguments.
                from typhon.objects.collections import ConstList
                if not method._ps.unify(ConstList(args), env):
                    raise RuntimeError
                # Run the block.
                rv = method._b.evaluate(env)

            return rv
        raise Refused(verb, args)
