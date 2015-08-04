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

def makePumpTube(pump):
    var upstream := var downstream := null
    var pause := null
    var stash := []

    return object pumpTube:
        to flowingFrom(fount):
            upstream := fount
            return pumpTube

        to receive(item):
            def pumped := pump.received(item)
            stash += pumped
            # If we no longer have a downstream, then buffer the received item
            # and pause upstream. We'll unpause on the next flowTo().
            if (downstream == null && pause == null):
                if (upstream != null):
                    pause := upstream.pauseFlow()
            else:
                pumpTube.flush()

        to flowStopped(reason :Str):
            pump.stopped(reason)

            if (downstream != null):
                downstream.flowStopped(reason)

        to flowAborted(reason :Str):
            pump.stopped(reason)

            if (downstream != null):
                downstream.flowAborted(reason)

        to flowTo(drain):
            # The drain must be fulfilled. We handle flow control, not
            # asynchrony.

            # Disconnect.
            if (drain == null):
                downstream := null
                return null

            # Contractual obligation: Fire flowingFrom() callback.
            def rv := drain.flowingFrom(pumpTube)
            downstream := drain

            # If there's any stashed output (leftovers, pushback, etc.) reflow
            # to the new drain.
            pumpTube.flush()

            # If we asked upstream to pause, ask them to unpause now.
            if (pause != null):
                pause.unpause()
                pause := null

            return rv

        to pauseFlow():
            return upstream.pauseFlow()

        to stopFlow():
            downstream.flowStopped()
            downstream := null
            return upstream.stopFlow()

        to abortFlow():
            downstream.flowAborted()
            downstream := null
            return upstream.abortFlow()

        to flush():
            while (stash.size() > 0 &! downstream == null):
                def [piece] + newStash := stash
                stash := newStash
                downstream.receive(piece)


[=> makePumpTube]
