imports => nullPump :DeepFrozen
exports (makeStatefulPump)

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

def makeStatefulPump(machine) as DeepFrozen:
    def State := machine.getStateGuard()
    def [var state :State, var size :Int] := machine.getInitialState()
    var buf := []

    return object statefulPump extends nullPump:
        to received(item) :List:
            buf += item
            while (buf.size() >= size):
                def data := buf.slice(0, size)
                buf := buf.slice(size, buf.size())
                def [newState, newSize] := machine.advance(state, data)
                state := newState
                size := newSize

            return machine.results()
