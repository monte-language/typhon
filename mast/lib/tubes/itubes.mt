imports
exports (Pump, Unpauser, Fount, Drain, Tube)

interface Pump:
    "A stream processor which does not care about flow control.

     Pumps transform incoming items each into zero or more outgoing
     elements."

    to started() :Void:
        "Flow has started; items will be received soon.

         Pumps should use this method to initialize any required mutable
         state."

    # XXX :Promise[List]
    to received(item):
        "Process an item and send zero or more items downstream.
        
         The return value must be a list of items, but it can be a promise."

    # XXX :(Double >= 0.0)
    to progressed(amount :Double) :Void:
        "The current flow control around the pump has updated its load.
        
         `amount` is 1.0 for every task queued further up the pipeline. Pumps
         might use this method to adjust their processing parameters to trade
         speed for memory or quality."

    to stopped(reason :Str) :Void:
        "Flow has stopped.

         Pumps should use this method to tear down any allocated resources
         that they may be holding."


interface Unpauser:
    "An unpauser."

    to unpause():
        "Remove the pause corresponding to this unpauser.

         Flow will resume when all extant pauses are removed, so unpausing
         this object will not necessarily cause flow to resume.

         Calling `unpause()` more than once will have no effect.

         Flow could resume during this turn; use an eventual send if you want
         to defer it to a subsequent turn.
        
         The spice must flow."


# XXX Fount[X]
interface Fount:
    "A source of streaming data."

    to flowTo(drain) :Any:
        "Designate a drain to receive data from this fount.

         Once called, flow could happen immediately, within the current turn;
         this fount must merely call `to flowingFrom(fount)` before starting
         to flow.
         
         The return value should be a fount which can `to flowTo()` another
         drain. This is typically achieved by returning the drain that was
         flowed to and treating it as a tube."

    to pauseFlow() :Unpauser:
        "Interrupt the flow.

         Returns an `Unpauser` which can resume flow."

    to stopFlow() :Void:
        "Terminate the flow.

         This fount should cleanly terminate its resources. This fount may
         send more data to its drain, but should eventually cease flow and
         call `to flowStopped()` on its drain when quiescent."

    to abortFlow() :Void:
        "Terminate the flow with extreme prejudice.

         This fount must not send any more data downstream. Instead, it must
         uncleanly release its resources and abort any further upstream flow."


# XXX Drain[X]
interface Drain:
    "A sink of streaming data."

    to flowingFrom(fount) :Any:
        "Inform this drain that a fount will be flowing to it.
        
         The return value is a fount which can `to flowTo()` another drain;
         this is normally done by treating this drain as a tube and returning
         itself."

    to receive(item) :Void:
        "Accept some data.

         This method is the main workhorse of the entire tube subsystem.
         Founts call `to receive()` on their drains repeatedly to move data
         downstream."

    to progress(amount :Double) :Void:
        "Inform a drain of incoming task load.
        
         In response to extra load, a drain may choose to pause its upstream
         founts; this backpressure should be propagated as far as necessary."

    to flowStopped(reason :Str):
        "Flow has ceased.

         This drain should allow itself to drain cleanly to the next drain in
         the flow or whatever external resource this drain represents, and
         then call `to flowStopped()` on the next drain."

    to flowAborted(reason :Str):
        "Flow has been aborted.

         This drain should uncleanly release its resources and abort the
         remainder of the downstream flow, if any."


interface Tube extends Drain, Fount:
    "A pressure-sensitive segment in a stream processing workflow."
