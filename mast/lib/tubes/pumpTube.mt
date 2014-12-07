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
            if (__equalizer.sameYet(downstream, null) && pause == null):
                pause := upstream.pauseFlow()
            else:
                pumpTube.flush()

        to progress(amount):
            pump.progressed(amount)
            if (downstream != null):
                downstream.progress(amount)

        to flowStopped():
            if (downstream != null):
                downstream.flowStopped()

        to flowTo(drain):
            # Be aware that the drain could be a promise.

            # Disconnect.
            if (__equalizer.sameYet(drain, null)):
                downstream := null
                return null

            downstream := drain

            def [p, r] := Ref.promise()
            when (downstream) ->
                r.resolve(drain.flowingFrom(pumpTube))

                # If there's any stashed output (leftovers, pushback, etc.) reflow
                # to the new drain.
                pumpTube.flush()

                # If we asked upstream to pause, ask them to unpause now.
                if (pause != null):
                    pause.unpause()
                    pause := null

            return p

        to pauseFlow():
            return upstream.pauseFlow()

        to stopFlow():
            downstream.flowStopped()
            downstream := null
            return upstream.stopFlow()

        to flush():
            if (__equalizer.optSame(downstream, null) == false):
                for item in stash:
                    downstream.receive(item)
                stash := []


[=> makePumpTube]
