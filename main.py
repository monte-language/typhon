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
import sys

from typhon.env import Environment
from typhon.errors import UserException
from typhon.load import load
from typhon.objects.vats import Vat, vatScope
from typhon.reactor import Reactor
from typhon.simple import simpleScope


def entryPoint(argv):
    if len(argv) < 2:
        print "No file provided?"
        return 1

    reactor = Reactor()
    vat = Vat(reactor)

    scope = simpleScope()
    scope.update(vatScope(vat))
    env = Environment(scope)

    terms = load(open(argv[1], "rb").read())
    for term in terms:
        print term.repr()
        try:
            print term.evaluate(env).repr()
        except UserException as ue:
            print "Caught exception:", ue.formatError()
            return 1

    # Run any remaining turns.
    while vat.hasTurns() or reactor.hasObjects():
        if vat.hasTurns():
            count = len(vat._pending)
            print "Taking", count, "turn(s) on", vat.repr()
            for _ in range(count):
                try:
                    vat.takeTurn()
                except UserException as ue:
                    print "Caught exception:", ue.formatError()

        if reactor.hasObjects():
            print "Performing I/O..."
            reactor.spin(vat.hasTurns())

    return 0


def target(*args):
    return entryPoint, None


if __name__ == "__main__":
    entryPoint(sys.argv)
