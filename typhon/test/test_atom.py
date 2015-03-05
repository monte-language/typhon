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

from unittest import TestCase

from typhon.atoms import getAtom


class TestAtom(TestCase):

    def testRepr(self):
        atom = getAtom(u"test", 5)
        self.assertEqual(repr(atom), u"Atom(test/5)")

    def testIdempotency(self):
        first = getAtom(u"test", 5)
        second = getAtom(u"test", 5)
        self.assertTrue(first is second)
