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
from typhon.simple import simpleScope


def entry_point(argv):
    if len(argv) < 2:
        print "No file provided?"
        return 1

    terms = load(open(argv[1], "rb").read())
    env = Environment(simpleScope())
    for term in terms:
        print term.repr()
        try:
            print term.evaluate(env).repr()
        except UserException as ue:
            print "Caught exception:", ue.formatError()
            return 1

    return 0


def target(*args):
    return entry_point, None


if __name__ == "__main__":
    entry_point(sys.argv)
