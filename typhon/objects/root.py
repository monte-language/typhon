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


class Object(object):

    # The attributes that all Objects have in common.
    _attrs_ = "stamps",

    # The auditor stamps on objects.
    stamps = []

    def __repr__(self):
        return self.repr()

    def repr(self):
        return "<object>"


def runnable(f):
    """
    Promote a function to a Monte object.

    The resulting object can be called multiple times to create multiple Monte
    objects.
    """

    name = f.__name__

    class runnableObject(Object):
        def repr(self):
            return "<%s>" % name

        def recv(self, verb, args):
            if verb == u"run":
                return f(args)
            raise Refused(verb, args)

    return runnableObject
