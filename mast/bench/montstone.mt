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

# Adapted from Dhrystone in C. I have pride in my compiler's optimizations, so
# I am not afraid to include the relatively poorly-written parts of this
# benchmark. ~ C.

def [=> makeEnum] := import("lib/enum")

def LOOPS :Int := 50000 # 500000

def [Enumeration, Ident1, Ident2, Ident3, Ident4, Ident5] := makeEnum(
    ["Ident1", "Ident2", "Ident3", "Ident4", "Ident5"])

def OneToThirty := Int
def OneToFifty := Int
def CapitalLetter := Char
def String30 := Str
def Array1Dim := List[Int]
def Array2Dim := List[List[Int]]

def makeRecord(var PtrComp, var Discr :Enumeration, var EnumComp :Enumeration,
               var IntComp :OneToFifty, var StringComp :String30):
    return object Record:
        to getPtrComp():
            return PtrComp

        to getPtrCompSlot():
            return &PtrComp

        to setPtrComp(x):
            PtrComp := x

        to getDiscr():
            return Discr

        to setDiscr(x):
            Discr := x

        to getEnumComp():
            return EnumComp

        to getEnumCompSlot():
            return &EnumComp

        to setEnumComp(x):
            EnumComp := x

        to getIntComp():
            return IntComp

        to getIntCompSlot():
            return &IntComp

        to setIntComp(x):
            IntComp := x

        to getStringComp():
            return StringComp

        to setStringComp(x):
            StringComp := x

def mallocRecord():
    return makeRecord(null, Ident1, Ident1, 0, "")

def structAssign(d, s):
    d.setPtrComp(s.getPtrComp())
    d.setDiscr(s.getDiscr())
    d.setEnumComp(s.getEnumComp())
    d.setIntComp(s.getIntComp())
    d.setStringComp(s.getStringComp())

# Package 1

var IntGlob :Int := 0
var BoolGlob :Bool := false
var Char1Glob :Char := '\x00'
var Char2Glob :Char := '\x00'
var Array1Glob :Array1Dim := ([0] * 51).diverge()
var Array2Glob :Array2Dim := [([0] * 51).diverge() for _ in 0..50].diverge()
var PtrGlb := null
var PtrGlbNext := null

# To avoid forward references, we define things before use, which makes the
# rest of the program read backwards. Sorry. ~ C.

def Func1(CharPar1 :CapitalLetter, CharPar2 :CapitalLetter) :Enumeration:
    def CharLoc1 :CapitalLetter := CharPar1
    def CharLoc2 :CapitalLetter := CharLoc1
    if (CharLoc2 != CharPar2):
        return Ident1
    else:
        return Ident2

def Func2(StrParI1 :String30, StrParI2 :String30) :Bool:
    var IntLoc :OneToThirty := 1
    # There's an underspecification here as to what the initialized value of
    # this variable should be.
    var CharLoc :CapitalLetter := 'A'

    while (IntLoc <= 1):
        if (Func1(StrParI1[IntLoc], StrParI2[IntLoc + 1]) == Ident1):
            CharLoc := 'A'
            IntLoc += 1
    if (CharLoc >= 'W' && CharLoc <= 'Z'):
        IntLoc := 7
    if (CharLoc == 'X'):
        return true
    else:
        if (StrParI1 > StrParI2):
            IntLoc += 7
            return true
        else:
            return false

def Func3(EnumParIn :Enumeration) :Bool:
    def EnumLoc :Enumeration := EnumParIn
    if (EnumLoc == Ident3):
        return true
    return false

def Proc8(Array1Par :Array1Dim, Array2Par :Array2Dim, IntParI1 :OneToFifty,
          IntParI2 :OneToFifty):
    def IntLoc :OneToFifty := IntParI1 + 5

    Array1Par[IntLoc] := IntParI2
    Array1Par[IntLoc + 1] := Array1Par[IntLoc]
    Array1Par[IntLoc + 30] := IntLoc
    for IntIndex in IntLoc..(IntLoc + 1):
        Array2Par[IntLoc][IntIndex] := IntLoc
    Array2Par[IntLoc][IntLoc - 1] += 1
    Array2Par[IntLoc + 20][IntLoc] := Array1Par[IntLoc]
    IntGlob := 5

def Proc7(IntParI1 :OneToFifty, IntParI2 :OneToFifty, &IntParOut):
    def IntLoc :OneToFifty := IntParI1 + 2
    IntParOut := IntParI2 + IntLoc

def Proc6(EnumParIn :Enumeration, &EnumParOut):
    EnumParOut := EnumParIn
    if (!Func3(EnumParIn)):
        EnumParOut := Ident4
    switch (EnumParIn):
        match ==Ident1:
            EnumParOut := Ident1
        match ==Ident2:
            if (IntGlob > 100):
                EnumParOut := Ident1
            else:
                EnumParOut := Ident4
        match ==Ident3:
            EnumParOut := Ident2
        match ==Ident4:
            pass
        match ==Ident5:
            EnumParOut := Ident3

def Proc5():
    Char1Glob := 'A'
    BoolGlob := false

def Proc4():
    var BoolLoc :Bool := Char1Glob == 'A'
    BoolLoc |= BoolGlob
    Char2Glob := 'B'

def Proc3(&PtrParOut):
    if (PtrGlb != null):
        PtrParOut := PtrGlb.getPtrComp()
    else:
        IntGlob := 100
    Proc7(10, IntGlob, PtrGlb.getIntCompSlot())

def Proc2(&IntParIO):
    var IntLoc :OneToFifty := IntParIO + 10
    var EnumLoc :Enumeration := Ident1

    while (true):
        if (Char1Glob == 'A'):
            IntLoc -= 1
            IntParIO := IntLoc - IntGlob
            EnumLoc := Ident1
        if (EnumLoc == Ident1):
            break

def Proc1(PtrParIn):
    structAssign(PtrParIn.getPtrComp(), PtrGlb)
    PtrParIn.setIntComp(5)
    PtrParIn.getPtrComp().setIntComp(PtrParIn.getIntComp())
    PtrParIn.getPtrComp().setPtrComp(PtrParIn.getPtrComp())
    Proc3(PtrParIn.getPtrCompSlot())
    if (PtrParIn.getPtrComp().getDiscr() == Ident1):
        PtrParIn.getPtrComp().setIntComp(6)
        Proc6(PtrParIn.getEnumComp(), PtrParIn.getPtrComp().getEnumCompSlot())
        PtrParIn.getPtrComp().setPtrComp(PtrGlb.getPtrComp())
        Proc7(PtrParIn.getPtrComp().getIntComp(), 10,
              PtrParIn.getPtrComp().getIntCompSlot())
    else:
        structAssign(PtrParIn, PtrParIn.getParComp())

def Proc0():
    var IntLoc1 :OneToFifty := 0
    var IntLoc2 :OneToFifty := 0
    var IntLoc3 :OneToFifty := 0
    var CharLoc :Char := '\x00'
    var EnumLoc :Enumeration := Ident1
    var String1Loc :String30 := ""
    var String2Loc :String30 := ""

    PtrGlb := mallocRecord()
    PtrGlbNext := mallocRecord()
    PtrGlb.setPtrComp(PtrGlbNext)
    PtrGlb.setDiscr(Ident1)
    PtrGlb.setEnumComp(Ident3)
    PtrGlb.setIntComp(40)
    PtrGlb.setStringComp("DHRYSTONE PROGRAM, SOME STRING")
    String1Loc := "DHRYSTONE PROGRAM, 1'ST STRING"
    Array2Glob[8][7] := 10

    for i in 0..!LOOPS:
        Proc5()
        Proc4()
        IntLoc1 := 2
        IntLoc2 := 3
        String2Loc := "DHRYSTONE PROGRAM, 2'ND STRING"
        EnumLoc := Ident2
        BoolGlob := !Func2(String1Loc, String2Loc)

        while (IntLoc1 < IntLoc2):
            IntLoc3 := 5 * IntLoc1 - IntLoc2
            Proc7(IntLoc1, IntLoc2, &IntLoc3)
            IntLoc1 += 1
        Proc8(Array1Glob, Array2Glob, IntLoc1, IntLoc3)
        Proc1(PtrGlb)
        for CharIndex in 'A'..Char2Glob:
            if (EnumLoc == Func1(CharIndex, 'C')):
                Proc6(Ident1, &EnumLoc)
        IntLoc3 := IntLoc2 * IntLoc1
        IntLoc2 := IntLoc3 // IntLoc1
        IntLoc2 := 7 * (IntLoc3 - IntLoc2) - IntLoc1
        Proc2(&IntLoc1)

Proc0()
