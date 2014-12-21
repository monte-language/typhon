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

from typhon.errors import UserException
from typhon.load import load
from typhon.nodes import evaluate
from typhon.objects.constants import NullObject
from typhon.optimizer import optimize
from typhon.scope import Scope


def obtainModule(path, recorder):
    with recorder.context("Deserialization"):
        terms = load(open(path, "rb").read())
    with recorder.context("Scope cleanup"):
        terms = [term.rewriteScope(Scope(), Scope()) for term in terms]
    with recorder.context("Optimization"):
        terms = [optimize(term) for term in terms]
    for term in terms:
        print "Optimized node:"
        print term.repr()
    return terms


def evaluateWithTraces(term, env):
    try:
        return evaluate(term, env)
    except UserException as ue:
        print "Caught exception:", ue.formatError()
        return None


def evaluateTerms(terms, env):
    result = NullObject
    for term in terms:
        result = evaluateWithTraces(term, env)
        if result is None:
            print "Evaluation returned None!"
        else:
            print result.toQuote()
    return result
