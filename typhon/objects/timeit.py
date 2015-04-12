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

import time

from typhon.atoms import getAtom
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapStr
from typhon.objects.root import runnable

RUN_2 = getAtom(u"run", 2)

@runnable(RUN_2)
def bench(args):
    obj = args[0]
    name = unwrapStr(args[1])

    print "Benchmarking", name

    # Step 1: Calibrate timing loop.
    print "Calibrating timing loop..."
    # Unroll do-while iteration.
    loops = 1
    print "Trying 1 loop..."
    taken = time.time()
    obj.call(u"run", [])
    taken = time.time() - taken
    while taken < 1.0 and loops < 100000000:
        loops *= 10
        print "Trying", loops, "loops..."
        acc = 0
        taken = time.time()
        while acc < loops:
            acc += 1
            obj.call(u"run", [])
        taken = time.time() - taken
        print "Took", taken, "seconds to run", loops, "loops"
    print "Okay! Will take", loops, "loops at", taken, "seconds"

    # Step 2: Take trials.
    print "Taking trials..."
    trialCount = 3 - 1
    # Unroll first iteration to get maximum.
    acc = 0
    taken = time.time()
    while acc < loops:
        acc += 1
        obj.call(u"run", [])
    taken = time.time() - taken
    result = taken
    while trialCount:
        trialCount -= 1
        acc = 0
        taken = time.time()
        while acc < loops:
            acc += 1
            obj.call(u"run", [])
        taken = time.time() - taken
        if taken < result:
            result = taken

    # Step 3: Calculate results.
    usec = taken * 1000000 / loops
    if usec < 1000:
        timing = "%f us/iteration" % usec
    else:
        msec = usec / 1000
        if msec < 1000:
            timing = "%f ms/iteration" % msec
        else:
            sec = msec / 1000
            timing = "%f s/iteration" % sec

    print name + u":", "Took %d loops in %f seconds (%s)" % (loops, taken,
                                                             timing)

    # All done!
    return NullObject
