interface Pump:
    "A stream processor which does not care about flow control.

     Pumps transform incoming items each into zero or more outgoing
     elements."

    to started():
        "Flow has started; items will be received soon.

         Pumps should use this method to initialize any required mutable
         state."

    to received(item):
        "Process an item and send zero or more items downstream.
        
         The return value must be a list of items, but it can be a promise."

    to progressed(amount :Double):
        "To be honest, this method's on the chopping block."

    to stopped():
        "Flow has stopped.

         Pumps should use this method to tear down any allocated resources
         that they may be holding."


interface Unpauser:
    "An unpauser."

    to unpause():
        "Remove the pause corresponding to this unpauser.

         Flow will resume when all extant pauses are removed, so unpausing
         this object will not necessarily cause flow to resume.

         Flow could resume during this turn.
        
         The spice must flow."


interface Fount:
    "A source of streaming data."

    to flowTo(drain):
        "Designate a drain to receive data from this fount.

         Once called, flow could happen immediately, within the current turn;
         this fount must merely call `to flowingFrom(fount)` before starting
         to flow.
         
         The return value should be a fount which can `to flowTo()` another
         drain. This is typically achieved by returning the drain that was
         flowed to and treating it as a tube."

    to pauseFlow() :Unpauser:
        "Interrupt the flow.

         An unpauser corresponding to the pause on this object is returned,
         which can be used to resume flow."

    to stopFlow():
        "Terminate the flow.

         This fount should cleanly terminate its resources. This fount may
         send more data to its drain, but should eventually cease flow and
         call `to flowStopped()` on its drain when quiescent."

    to abortFlow():
        "Terminate the flow with extreme prejudice.

         This fount must not send any more data downstream. Instead, it must
         uncleanly release its resources and abort any further upstream flow."


interface Drain:
    "A sink of streaming data."

    to flowingFrom(fount): 
        "Inform this drain that a fount will be flowing to it.
        
         The return value is a fount which can `to flowTo()` another drain;
         this is normally done by treating this drain as a tube and returning
         itself."

    to receive(item):
        "Accept some data.

         This method is the main workhorse of the entire tube subsystem.
         Founts call `to receive()` on their drains repeatedly to move data
         downstream."

    to progress(amount :Double):
        "Deprecated."

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


[=> Pump, => Drain, => Fount, => Tube]
