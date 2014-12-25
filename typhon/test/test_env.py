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

from typhon.env import Environment
from typhon.errors import UserException
from typhon.objects.constants import NullObject
from typhon.objects.slots import FinalSlot


class TestEnv(TestCase):

    def testFinalImmutability(self):
        env = Environment([], None, 1)
        env.createSlot(0, FinalSlot(NullObject))
        self.assertRaises(UserException, env.putValue, 0, NullObject)
