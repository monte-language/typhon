import "unittest" =~ [=> unittest :Any]
import "lib/iterators" =~ [=> zip :DeepFrozen]
exports (makeEnum)
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

def makeEnumObject(i :DeepFrozen, name :DeepFrozen) as DeepFrozen:
    return object enumObject as DeepFrozen:
        to getName():
            return name

        to _printOn(out):
            out.print(name)

        to asInteger() :Int:
            return i

def DF :Same[DeepFrozen] := DeepFrozen

object makeEnum as DeepFrozen:
    to run(names :List[Str]):
        "Make an enumeration from a list of names.

         def [Enum, first, second] := makeEnum([\"first\", \"second\"])
        "

        def enums :List[DeepFrozen] := [for i => name in (names)
                                        makeEnumObject(i, name)]
        def enumSet :Set[DeepFrozen] := enums.asSet()

        def EnumGuard.coerce(specimen, ej) :DF as DeepFrozen implements SubrangeGuard[DeepFrozen]:
            "Require `specimen` to be a member of an enumeration."

            if (!enumSet.contains(specimen)):
                throw.eject(ej, `$specimen is not one of $enums`)
            return specimen

        return [EnumGuard] + enums

    to asMap(names :List[Str]):
        def [EnumGuard :DeepFrozen] + enumList := makeEnum(names)
        def enums :DeepFrozen := _makeMap.fromPairs(_makeList.fromIterable(zip(names, enumList)))
        return object enumMap extends enums implements DeepFrozen:

            to _conformTo(_guard) :Map:
                return enums

            to _printOn(out):
                out.print("<Enum: ")
                out.print(enums)
                out.print(">")

            to getGuard():
                return EnumGuard

def testEnum(assert):
    def [Fubar, FOO, BAR] := makeEnum(["foo", "bar"])
    assert.equal(FOO, FOO)
    assert.equal(BAR, BAR)
    assert.notEqual(FOO, BAR)
    assert.ejects(fn ej {def _ :Fubar exit ej := 42})
    assert.doesNotEject(fn ej {def _ :Fubar exit ej := FOO})

def testEnumSubrangeDF(assert):
    def [Fubar, FOO :Fubar, BAR :Fubar] := makeEnum(["foo", "bar"])
    def df.foo() as DeepFrozen:
        return [FOO, BAR]
    assert.equal(df.foo(), [FOO, BAR])

def testEnumMap(assert):
    def enums := makeEnum.asMap(["red", "blue"])
    assert.doesNotEject(fn ej { def _ :(enums.getGuard()) exit ej := enums["red"] })
    assert.doesNotEject(fn ej { def [ "red" => _, "blue" => _ ] exit ej := (enums :Map) })
    assert.equal(M.toString(enums), `<Enum: ["red" => red, "blue" => blue]>`)

unittest([
    testEnum,
    testEnumSubrangeDF,
    testEnumMap
])
