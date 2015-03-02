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

def makeEnumObject(i :Int, name):
    return object enumObject:
        to _printOn(out):
            out.print(name)

        to asInteger() :Int:
            return i

def makeEnum(names :List):
    def enums := [makeEnumObject(i, name) for i => name in names]
    def enumSet := enums.asSet()

    object EnumGuard:
        to coerce(specimen, ej):
            if (!enums.contains(specimen)):
                throw.eject(ej, `$specimen is not one of $enums`)
            return specimen

        to makeSlot(var value):
            return object enumSlot:
                to get():
                    return value
                to put(v):
                    value := EnumGuard.coerce(v, null)

    return [EnumGuard] + enums

def testEnum(assert):
    def [Fubar, FOO, BAR] := makeEnum(["foo", "bar"])
    assert.equal(FOO, FOO)
    assert.equal(BAR, BAR)
    assert.notEqual(FOO, BAR)
    assert.ejects(fn ej {def x :Fubar exit ej := 42})
    assert.doesNotEject(fn ej {def x :Fubar exit ej := FOO})

unittest([testEnum])

[=> makeEnum]
