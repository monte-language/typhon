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

from unittest import TestCase

from typhon.errors import Ejecting, UserException
from typhon.objects.data import IntObject
from typhon.objects.ejectors import Ejector
from typhon.objects.guards import predGuard


class TestPredGuard(TestCase):

    def testCoerceInt(self):
        @predGuard
        def g(o):
            return o.getInt() == 42

        i = IntObject(42)
        result = g().recv(u"coerce", [i, None])
        self.assertEqual(i.getInt(), 42)

    def testCoerceIntFailure(self):
        @predGuard
        def g(o):
            return o.getInt() == 42

        i = IntObject(41)
        self.assertRaises(UserException, g().recv, u"coerce", [i, None])

    def testCoerceIntEjection(self):
        @predGuard
        def g(o):
            return o.getInt() == 42

        i = IntObject(41)
        with Ejector() as ej:
            self.assertRaises(Ejecting, g().recv, u"coerce", [i, ej])
