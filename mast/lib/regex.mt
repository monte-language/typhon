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

def [=> makeDerp, => anything, => ex] | _ := import("lib/parsers/derp")

def anyChar := ex('.') % fn _ {anything}

def regex := anyChar

object re__quasiParser:
    to valueMaker(pieces):
        var p := regex
        for chunk in pieces:
            p := p.feedMany(chunk)
        return object hurp:
            to substitute(values):
                return p

traceln(re`.`)
