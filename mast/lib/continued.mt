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

# Continued fractions. Nearly all maths here comes from Gosper in the early
# 70s. Nothing interesting here, aside from the wonders of maths.

def [=> makeEnum] | _ := import("lib/enum")

object infinity:
    to _printOn(out):
        out.print("∞")

def [Finity, FINITE, INFINITE] := makeEnum(["finite", "infinite"])


def makeDigitExtractor(machine, base :Int):
    var a :Int := 1
    var b :Int := 0
    var c :Int := 0
    var d :Int := 1

    def shouldFeed() :Bool:
        if (c == 0 || d == 0):
            return true

        return a // c != b // d

    return object digitExtractor:
        to _printOn(out):
            out.print(`<digitExtractor($machine, $base)>`)

        to produceDigit(ej) :Int:
            # traceln(`Considering feeding <$a $b $c $d>`)
            var exhausted := false
            while (shouldFeed() && !exhausted):
                # Ingest.
                escape exhaust:
                    def p := machine.produceTerm(exhaust)
                    def olda := a
                    def oldc := c
                    a := a * p + b
                    c := c * p + d
                    b := olda
                    d := oldc
                catch _:
                    # traceln(`Exhausted!`)
                    exhausted := true
                    b := a
                    d := c
                # traceln(`Fed <$a $b $c $d>`)

            # a // c == b // d now, so we can extract a digit.
            def digit := a // c
            # XXX compiler bug
            if (digit == 0 & a == 0 & b == 0):
                # Finite number of digits in this base! We're done.
                throw.eject(ej, "Finished with extraction")

            # Egest a value with the given base.
            a := base * (a - digit * c)
            b := base * (b - digit * d)
            # traceln(`Extracted $digit leaving <$a $b $c $d>`)

            return digit


def makeMachine(feed):
    var a :Int := 1
    var b :Int := 0
    var c :Int := 0
    var d :Int := 1

    var terms :List[Int] := []
    var finity :Finity := INFINITE

    def ingest(p :Int, q :Int):
        def olda := a
        def oldc := c
        a := a * p + b
        c := c * p + d
        b := olda * q
        d := oldc * q

    def egest(q :Int):
        def olda := a
        def oldb := b
        a := c
        b := d
        c := olda - c * q
        d := oldb - d * q

    def shouldFeed() :Bool:
        if (c == 0 || d == 0):
            return true
        return a // c != b // d

    return object machine:
        to _printOn(out):
            if (finity == FINITE):
                switch (terms):
                    match ==[]:
                        out.print("[]")
                    match [head] + ==[]:
                        out.print(`[$head]`)
                    match [head] + tail:
                        def commaTail := ", ".join([`$i` for i in tail])
                        out.print(`[$head; $commaTail]`)
            else:
                switch (terms):
                    match ==[]:
                        out.print("[…]")
                    match [head] + ==[]:
                        out.print(`[$head; …]`)
                    match [head] + tail:
                        def commaTail := ", ".join([`$i` for i in tail])
                        out.print(`[$head; $commaTail, …]`)

        to forceFeed(p, q):
            ingest(p, q)

        to produceTerm(_) :Int:
            # Does this clause feel ironic to you?
            if (finity == FINITE):
                return infinity

            while (shouldFeed()):
                def [p, q] := feed()
                ingest(p, q)

            def term := a // c
            egest(term)
            terms with= term
            return term

        to getTerms() :List[Int]:
            return terms

        to extractDigits(base :Int):
            return makeDigitExtractor(machine, base)


object continued:
    to pi():
        # 0 + 4/(1 + 1**2/(3 + 2**2/(5 + 3**2/(...))))
        # Converges linearly, requires a force feeding at the beginning.
        var p := 1
        var q := 1

        def feed():
            # Old trick: Difference of squares is an odd number which scales
            # linearly. Avoids multiplication of bigints here, assuming we get
            # that big.
            p += 2
            q += p
            return [p, q]

        def machine := makeMachine(feed)
        machine.forceFeed(0, 4)
        # Work it out above; this term gets skipped if we don't feed it here.
        machine.forceFeed(1, 1)
        return machine


def testPiDigits(assert):
    def pi := continued.pi()
    def extractor := pi.extractDigits(10)
    # That's all the digits I know.
    for digit in [3, 1, 4, 1, 5, 9, 2, 6]:
        assert.equal(extractor.produceDigit(null), digit)

unittest([testPiDigits])


def piBench():
    def pi := continued.pi().extractDigits(10)
    return [pi.produceDigit(null) for _ in 0..!100]


bench(piBench, "100 digits of pi")


[=> continued]
